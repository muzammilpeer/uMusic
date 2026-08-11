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
    private let foregroundSession: URLSession
    private let stagingDirectory: URL

    public init(identifier: String, stagingDirectory: URL) {
        self.stagingDirectory = stagingDirectory
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
        // Match the proven v1 offline transport. Async download(for:) is a
        // foreground API and must use a default configuration, not a background
        // session or the playback session singleton.
        let foreground = URLSessionConfiguration.default
        foreground.waitsForConnectivity = true
        foreground.timeoutIntervalForRequest = 60
        foreground.timeoutIntervalForResource = 60 * 60
        // A user-triggered full-library refresh runs a bounded worker per active
        // processor. Match URLSession's per-host allowance to that worker pool so
        // the transport does not silently serialize those downloads.
        foreground.httpMaximumConnectionsPerHost = max(1, ProcessInfo.processInfo.activeProcessorCount)
        foreground.isDiscretionary = false
        foregroundSession = URLSession(configuration: foreground)
        super.init()
    }

    public func download(_ request: MediaDownloadRequest, allowsCellular: Bool) async throws -> DownloadedMedia {
        // Playback tickets are deliberately short lived. Start user-requested
        // downloads immediately rather than allowing a background session to defer
        // the request until after its signed URL expires. Existing background tasks
        // from older builds are still restored and committed by restoreTasks().
        return try await foregroundDownload(request, allowsCellular: allowsCellular)
    }

    private func foregroundDownload(_ request: MediaDownloadRequest, allowsCellular: Bool) async throws -> DownloadedMedia {
        var urlRequest = URLRequest(url: request.ticket.url)
        urlRequest.allowsCellularAccess = allowsCellular
        let (temporaryURL, response) = try await foregroundSession.download(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OfflineDownloadError.unsuccessfulResponse
        }
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let stable = stagingDirectory.appending(path: "\(UUID().uuidString).download")
        try FileManager.default.moveItem(at: temporaryURL, to: stable)
        return DownloadedMedia(request: request, temporaryURL: stable)
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

    public func removeAllDownloads() async throws {
        for task in active.values { task.cancel() }
        active.removeAll()
        for trackID in Array(entries.keys) {
            guard let entry = entries[trackID] else { continue }
            let file = root.appending(path: entry.relativePath)
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            entries.removeValue(forKey: trackID)
        }
        currentTrackID = nil
        await persistIndex()
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

public enum OfflineDownloadError: Error, LocalizedError {
    case invalidTaskMetadata, expiredTicket, unsuccessfulResponse, sizeMismatch, checksumMismatch, quotaExceeded, invalidQuota, currentlyPlaying

    public var errorDescription: String? {
        switch self {
        case .invalidTaskMetadata: "The restored download metadata is invalid."
        case .expiredTicket: "The server download ticket expired."
        case .unsuccessfulResponse: "The server rejected the media download."
        case .sizeMismatch: "The downloaded file size did not match the server metadata."
        case .checksumMismatch: "The downloaded file failed integrity verification."
        case .quotaExceeded: "The offline storage quota is too small."
        case .invalidQuota: "The offline storage quota is invalid."
        case .currentlyPlaying: "The currently playing download cannot be removed."
        }
    }
}
