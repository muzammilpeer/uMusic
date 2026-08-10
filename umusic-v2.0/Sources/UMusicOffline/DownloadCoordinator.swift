import CryptoKit
import Foundation
import UMusicDomain
import UMusicSupport

public struct MediaDownloadRequest: Codable, Sendable {
    public let track: TrackSummary
    public let ticket: PlaybackTicket
    public init(track: TrackSummary, ticket: PlaybackTicket) { self.track = track; self.ticket = ticket }
}

public struct DownloadedMedia: Sendable {
    public let request: MediaDownloadRequest
    public let temporaryURL: URL
    public init(request: MediaDownloadRequest, temporaryURL: URL) { self.request = request; self.temporaryURL = temporaryURL }
}

public protocol MediaDownloadTransport: Sendable {
    var recoveredDownloads: AsyncStream<DownloadedMedia> { get }
    func download(_ request: MediaDownloadRequest, allowsCellular: Bool) async throws -> DownloadedMedia
    func restoreTasks() async
}

public final class BackgroundMediaDownloadTransport: NSObject, MediaDownloadTransport, @unchecked Sendable {
    public let recoveredDownloads: AsyncStream<DownloadedMedia>
    private let delegate: BackgroundDownloadDelegate
    private let unmeteredSession: URLSession
    private let cellularSession: URLSession

    public init(identifier: String, stagingDirectory: URL) {
        let stream = AsyncStream<DownloadedMedia>.makeStream()
        recoveredDownloads = stream.stream
        delegate = BackgroundDownloadDelegate(stagingDirectory: stagingDirectory, recovered: stream.continuation)
        let unmetered = URLSessionConfiguration.background(withIdentifier: "\(identifier).unmetered")
        unmetered.allowsCellularAccess = false
        unmetered.isDiscretionary = false
        let cellular = URLSessionConfiguration.background(withIdentifier: "\(identifier).cellular")
        cellular.allowsCellularAccess = true
        cellular.isDiscretionary = false
        unmeteredSession = URLSession(configuration: unmetered, delegate: delegate, delegateQueue: nil)
        cellularSession = URLSession(configuration: cellular, delegate: delegate, delegateQueue: nil)
        super.init()
    }

    public func download(_ request: MediaDownloadRequest, allowsCellular: Bool) async throws -> DownloadedMedia {
        let session = allowsCellular ? cellularSession : unmeteredSession
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request.ticket.url)
            task.taskDescription = try? String(data: JSONEncoder().encode(request), encoding: .utf8)
            delegate.register(taskIdentifier: task.taskIdentifier, continuation: continuation)
            task.resume()
        }
    }

    public func restoreTasks() async {
        _ = await unmeteredSession.allTasks
        _ = await cellularSession.allTasks
    }
}

private final class BackgroundDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let stagingDirectory: URL
    private let recovered: AsyncStream<DownloadedMedia>.Continuation
    private let lock = NSLock()
    private var continuations: [Int: CheckedContinuation<DownloadedMedia, Error>] = [:]

    init(stagingDirectory: URL, recovered: AsyncStream<DownloadedMedia>.Continuation) {
        self.stagingDirectory = stagingDirectory; self.recovered = recovered
    }

    func register(taskIdentifier: Int, continuation: CheckedContinuation<DownloadedMedia, Error>) {
        lock.withLock { continuations[taskIdentifier] = continuation }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let description = downloadTask.taskDescription,
                  let data = description.data(using: .utf8) else { throw OfflineDownloadError.invalidTaskMetadata }
            let request = try JSONDecoder().decode(MediaDownloadRequest.self, from: data)
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            let stable = stagingDirectory.appending(path: "\(UUID().uuidString).download")
            try FileManager.default.moveItem(at: location, to: stable)
            let value = DownloadedMedia(request: request, temporaryURL: stable)
            let continuation = lock.withLock { continuations.removeValue(forKey: downloadTask.taskIdentifier) }
            if let continuation { continuation.resume(returning: value) } else { recovered.yield(value) }
        } catch {
            let continuation = lock.withLock { continuations.removeValue(forKey: downloadTask.taskIdentifier) }
            continuation?.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let continuation = lock.withLock { continuations.removeValue(forKey: task.taskIdentifier) }
        continuation?.resume(throwing: error)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier else { return }
        BackgroundDownloadCompletionRegistry.shared.complete(identifier: identifier)
    }
}

public final class BackgroundDownloadCompletionRegistry: @unchecked Sendable {
    public static let shared = BackgroundDownloadCompletionRegistry()
    private let lock = NSLock()
    private var handlers: [String: @Sendable () -> Void] = [:]
    private init() {}
    public func register(identifier: String, completion: @escaping @Sendable () -> Void) {
        lock.withLock { handlers[identifier] = completion }
    }
    public func complete(identifier: String) {
        let completion = lock.withLock { handlers.removeValue(forKey: identifier) }
        completion?()
    }
}

public actor DownloadCoordinator: OfflineManaging, CachedMediaLocating {
    private let root: URL
    private let indexURL: URL
    private let transport: any MediaDownloadTransport
    private let tickets: any PlaybackTicketAPI
    private let authentication: any AuthenticationManaging
    private let logger: any RedactedLogging
    private var entries: [UUID: OfflineMediaEntry]
    private var quotaBytes: Int64
    private var allowsCellular: Bool
    private var currentTrackID: UUID?
    private var active: [UUID: Task<Void, Error>] = [:]

    public init(root: URL, transport: any MediaDownloadTransport, tickets: any PlaybackTicketAPI, authentication: any AuthenticationManaging, initialQuotaBytes: Int64 = 500 * 1_024 * 1_024, allowsCellular: Bool = false, logger: any RedactedLogging = RedactedLogger(category: "offline")) {
        self.root = root; indexURL = root.appending(path: "index-v1.json")
        self.transport = transport; self.tickets = tickets; self.authentication = authentication; self.logger = logger
        let stored = Self.loadIndex(from: root.appending(path: "index-v1.json"))
        entries = Dictionary(uniqueKeysWithValues: stored.entries.map { ($0.trackID, $0) })
        quotaBytes = stored.quotaBytes > 0 ? stored.quotaBytes : max(initialQuotaBytes, 0)
        self.allowsCellular = stored.hasPolicy ? stored.allowsCellular : allowsCellular
        Task { await transport.restoreTasks() }
        Task { await self.consumeRecoveredDownloads() }
    }

    public func storageSnapshot() async -> OfflineStorageSnapshot {
        OfflineStorageSnapshot(usedBytes: usedBytes, quotaBytes: quotaBytes, entries: entries.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }, allowsCellular: allowsCellular, activeDownloadCount: active.count)
    }

    public func cachedFile(for trackID: UUID) async -> URL? {
        guard let entry = entries[trackID], entry.state == .ready else { return nil }
        let url = root.appending(path: entry.relativePath)
        guard FileManager.default.fileExists(atPath: url.path), (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) == entry.bytes else {
            entries.removeValue(forKey: trackID); await persistIndex(); return nil
        }
        entries[trackID] = OfflineMediaEntry(trackID: entry.trackID, title: entry.title, artist: entry.artist, relativePath: entry.relativePath, checksum: entry.checksum, bytes: entry.bytes, retention: entry.retention, state: .ready, lastAccessedAt: Date(), predictedUtility: entry.predictedUtility)
        return url
    }

    public func setCurrentlyPlaying(trackID: UUID?) async { currentTrackID = trackID }

    public func download(_ track: TrackSummary, retention: OfflineRetention) async throws {
        if let existing = entries[track.id], existing.state == .ready {
            if retention == .pinned && existing.retention != .pinned {
                entries[track.id] = replacing(existing, retention: .pinned); await persistIndex()
            }
            return
        }
        if let task = active[track.id] {
            try await task.value
            if retention == .pinned, let existing = entries[track.id], existing.retention != .pinned {
                entries[track.id] = replacing(existing, retention: .pinned); await persistIndex()
            }
            return
        }
        let task = Task { try await self.performDownload(track, retention: retention) }
        active[track.id] = task
        do { try await task.value; active.removeValue(forKey: track.id) }
        catch { active.removeValue(forKey: track.id); throw error }
    }

    public func removeDownload(trackID: UUID) async throws {
        guard trackID != currentTrackID else { throw OfflineDownloadError.currentlyPlaying }
        active[trackID]?.cancel(); active.removeValue(forKey: trackID)
        if let entry = entries.removeValue(forKey: trackID) {
            try? FileManager.default.removeItem(at: root.appending(path: entry.relativePath))
            await persistIndex()
        }
    }

    public func setQuota(bytes: Int64) async throws {
        guard bytes >= 0 else { throw OfflineDownloadError.invalidQuota }
        let old = quotaBytes; quotaBytes = bytes
        do { try evict(toFitAdditionalBytes: 0); await persistIndex() }
        catch { quotaBytes = old; throw error }
    }

    public func setAllowsCellular(_ allowed: Bool) async { allowsCellular = allowed; await persistIndex() }

    public func reconcile() async {
        let media = root.appending(path: "media", directoryHint: .isDirectory)
        let known = Set(entries.values.map(\.relativePath))
        if let files = try? FileManager.default.contentsOfDirectory(at: media, includingPropertiesForKeys: nil) {
            for file in files where !known.contains("media/\(file.lastPathComponent)") { try? FileManager.default.removeItem(at: file) }
        }
        for (id, entry) in entries where !FileManager.default.fileExists(atPath: root.appending(path: entry.relativePath).path) { entries.removeValue(forKey: id) }
        try? evict(toFitAdditionalBytes: 0); await persistIndex()
    }

    private func performDownload(_ track: TrackSummary, retention: OfflineRetention) async throws {
        let server = try await authentication.currentServer(); let token = try await authentication.validAccessToken()
        guard let ticket = try await tickets.tickets(server: server, accessToken: token, trackIDs: [track.id]).first,
              ticket.expiresAt > Date() else { throw OfflineDownloadError.expiredTicket }
        try evict(toFitAdditionalBytes: ticket.bytes)
        let downloaded = try await transport.download(.init(track: track, ticket: ticket), allowsCellular: allowsCellular)
        try Task.checkCancellation()
        try await commit(downloaded, retention: retention)
    }

    private func commit(_ downloaded: DownloadedMedia, retention: OfflineRetention) async throws {
        let ticket = downloaded.request.ticket
        defer { try? FileManager.default.removeItem(at: downloaded.temporaryURL) }
        let values = try downloaded.temporaryURL.resourceValues(forKeys: [.fileSizeKey])
        guard Int64(values.fileSize ?? -1) == ticket.bytes else { throw OfflineDownloadError.sizeMismatch }
        guard try Self.sha256(downloaded.temporaryURL) == ticket.checksum.lowercased() else { throw OfflineDownloadError.checksumMismatch }
        try evict(toFitAdditionalBytes: ticket.bytes)
        let directory = root.appending(path: "media", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: "\(ticket.trackID.uuidString.lowercased()).mp3")
        let partial = directory.appending(path: ".\(UUID().uuidString).partial")
        try FileManager.default.moveItem(at: downloaded.temporaryURL, to: partial)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: partial, to: destination)
        entries[ticket.trackID] = OfflineMediaEntry(trackID: ticket.trackID, title: downloaded.request.track.title, artist: downloaded.request.track.artist, relativePath: "media/\(destination.lastPathComponent)", checksum: ticket.checksum.lowercased(), bytes: ticket.bytes, retention: retention, state: .ready)
        await persistIndex()
    }

    private func consumeRecoveredDownloads() async {
        for await value in transport.recoveredDownloads {
            do { try await commit(value, retention: .rolling) }
            catch { try? FileManager.default.removeItem(at: value.temporaryURL); logger.error("restored_download_failed", fields: []) }
        }
    }

    private var usedBytes: Int64 { entries.values.reduce(0) { $0 + $1.bytes } }

    private func evict(toFitAdditionalBytes additional: Int64) throws {
        guard additional <= quotaBytes else { throw OfflineDownloadError.quotaExceeded }
        var required = usedBytes + additional - quotaBytes
        guard required > 0 else { return }
        let candidates = entries.values.filter { $0.retention == .rolling && $0.trackID != currentTrackID }.sorted {
            if $0.predictedUtility != $1.predictedUtility { return $0.predictedUtility < $1.predictedUtility }
            return $0.lastAccessedAt < $1.lastAccessedAt
        }
        for entry in candidates where required > 0 {
            try? FileManager.default.removeItem(at: root.appending(path: entry.relativePath))
            entries.removeValue(forKey: entry.trackID); required -= entry.bytes
        }
        if required > 0 { throw OfflineDownloadError.quotaExceeded }
    }

    private func persistIndex() async {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let value = StoredOfflineIndex(schemaVersion: 1, entries: Array(entries.values), quotaBytes: quotaBytes, allowsCellular: allowsCellular, hasPolicy: true)
            try JSONEncoder().encode(value).write(to: indexURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch { logger.error("offline_index_save_failed", fields: []) }
    }

    private func replacing(_ entry: OfflineMediaEntry, retention: OfflineRetention) -> OfflineMediaEntry {
        OfflineMediaEntry(trackID: entry.trackID, title: entry.title, artist: entry.artist, relativePath: entry.relativePath, checksum: entry.checksum, bytes: entry.bytes, retention: retention, state: entry.state, lastAccessedAt: entry.lastAccessedAt, predictedUtility: entry.predictedUtility)
    }

    private static func loadIndex(from url: URL) -> StoredOfflineIndex {
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(StoredOfflineIndex.self, from: data), value.schemaVersion == 1 else { return .empty }
        return value
    }

    private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var digest = SHA256()
        while true { let data = try handle.read(upToCount: 1_048_576) ?? Data(); if data.isEmpty { break }; digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private struct StoredOfflineIndex: Codable {
    let schemaVersion: Int; let entries: [OfflineMediaEntry]; let quotaBytes: Int64; let allowsCellular: Bool; let hasPolicy: Bool
    static let empty = StoredOfflineIndex(schemaVersion: 1, entries: [], quotaBytes: 0, allowsCellular: false, hasPolicy: false)
}

public enum OfflineDownloadError: Error { case invalidTaskMetadata, expiredTicket, sizeMismatch, checksumMismatch, quotaExceeded, invalidQuota, currentlyPlaying }
