import CryptoKit
import Foundation
import Network
#if os(iOS)
import UIKit
#endif

enum OfflineError: LocalizedError {
    case checksumMismatch, insufficientStorage, policyDeferred
    var errorDescription: String? {
        switch self {
        case .checksumMismatch: "Downloaded MP3 checksum did not match the manifest."
        case .insufficientStorage: "The offline storage quota is too small for this session."
        case .policyDeferred: "Waiting for the configured Wi-Fi or charging condition."
        }
    }
}

actor OfflineManager {
    static let shared = OfflineManager()

    private let root: URL
    private let indexURL: URL
    private let session: URLSession
    private var index: [UUID: CachedTrack]
    private(set) var preferences: OfflinePreferences

    init(root: URL? = nil, preferences: OfflinePreferences = OfflinePreferences()) {
        let base = root ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appending(path: "uMusic/offline")
        self.root = base
        indexURL = base.appending(path: "index.json")
        self.preferences = preferences
        index = (try? Data(contentsOf: indexURL)).flatMap {
            try? JSONDecoder.uMusic.decode([UUID: CachedTrack].self, from: $0)
        } ?? [:]
        // `download(for:)` is an async completion-handler API and cannot be used
        // with a background configuration. Keep this session foreground and
        // connectivity-aware; a true background implementation requires a
        // URLSessionDownloadDelegate and task restoration.
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.isDiscretionary = false
        session = URLSession(configuration: configuration)
    }

    func prepare(
        manifest: SyncManifest, force: Bool = false
    ) async -> (downloaded: [UUID], failed: [UUID]) {
        let missing = manifest.entries.filter { entry in
            if force { return true }
            guard let cached = index[entry.trackID] else { return true }
            return cached.sha256 != entry.sha256
                || !FileManager.default.fileExists(atPath: fileURL(cached).path)
        }
        var downloaded: [UUID] = []
        var failed: [UUID] = []
        for entry in missing {
            let existingBytes = index[entry.trackID]?.sizeBytes ?? 0
            guard cachedBytes() - existingBytes + entry.sizeBytes <= preferences.quotaBytes else {
                failed.append(entry.trackID)
                continue
            }
            do {
                try await download(entry, pinned: true, kind: .prepared)
                downloaded.append(entry.trackID)
            } catch {
                failed.append(entry.trackID)
            }
        }
        for entry in manifest.entries where index[entry.trackID] != nil {
            index[entry.trackID]?.pinned = true
        }
        persist()
        return (downloaded, failed)
    }

    func prefetch(_ entries: [ManifestEntry]) async {
        for entry in entries where index[entry.trackID] == nil {
            try? await download(entry, pinned: false, kind: .rolling)
        }
        evictRollingCacheIfNeeded()
    }

    func localURL(for trackID: UUID) -> URL? {
        guard var cached = index[trackID], FileManager.default.fileExists(atPath: fileURL(cached).path)
        else { return nil }
        cached.lastAccessed = Date()
        index[trackID] = cached
        persist()
        return fileURL(cached)
    }

    func cachedTracks() -> [CachedTrack] {
        index.values.sorted { $0.lastAccessed > $1.lastAccessed }
    }

    func isCached(_ trackID: UUID) -> Bool {
        guard let cached = index[trackID] else { return false }
        return FileManager.default.fileExists(atPath: fileURL(cached).path)
    }

    func sync(_ entry: ManifestEntry, force: Bool = false) async throws {
        let existingBytes = index[entry.trackID]?.sizeBytes ?? 0
        guard cachedBytes() - existingBytes + entry.sizeBytes <= preferences.quotaBytes else {
            throw OfflineError.insufficientStorage
        }
        if force, let cached = index[entry.trackID] {
            try? FileManager.default.removeItem(at: fileURL(cached))
            index.removeValue(forKey: entry.trackID)
        }
        if !isCached(entry.trackID) {
            try await download(entry, pinned: true, kind: .prepared)
        }
    }

    func cachedBytes() -> Int64 { index.values.reduce(0) { $0 + $1.sizeBytes } }

    func deviceFreeBytes() -> Int64 {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    func remove(_ trackID: UUID) {
        guard let cached = index.removeValue(forKey: trackID) else { return }
        try? FileManager.default.removeItem(at: fileURL(cached))
        persist()
    }

    func clearAll() {
        for cached in index.values {
            try? FileManager.default.removeItem(at: fileURL(cached))
        }
        index.removeAll()
        persist()
    }

    func unpinAllPrepared() {
        for id in index.keys { index[id]?.pinned = false }
        evictRollingCacheIfNeeded()
        persist()
    }

    func updatePreferences(_ value: OfflinePreferences) {
        preferences = value
        enforceQuota()
    }

    private func download(_ entry: ManifestEntry, pinned: Bool, kind: CachedTrack.Kind) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let part = root.appending(path: "\(entry.trackID).mp3.part")
        let complete = root.appending(path: "\(entry.trackID).mp3")
        let offset = (try? FileManager.default.attributesOfItem(atPath: part.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        var request = URLRequest(url: entry.downloadURL)
        request.allowsCellularAccess = !preferences.wifiOnly
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        let (temporary, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...206).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        if offset > 0, http.statusCode == 206 {
            let handle = try FileHandle(forWritingTo: part)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(contentsOf: temporary))
            try handle.close()
        } else {
            try? FileManager.default.removeItem(at: part)
            try FileManager.default.moveItem(at: temporary, to: part)
        }
        guard try sha256(part) == entry.sha256 else {
            try? FileManager.default.removeItem(at: part)
            throw OfflineError.checksumMismatch
        }
        try? FileManager.default.removeItem(at: complete)
        try FileManager.default.moveItem(at: part, to: complete)
        index[entry.trackID] = CachedTrack(
            id: entry.trackID, title: entry.title, sha256: entry.sha256,
            sizeBytes: entry.sizeBytes, localFilename: complete.lastPathComponent,
            pinned: pinned, lastAccessed: Date(), kind: kind
        )
        persist()
    }

    private func sha256(_ url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fileURL(_ cached: CachedTrack) -> URL { root.appending(path: cached.localFilename) }

    private func evictRollingCacheIfNeeded() {
        var total = index.values.reduce(Int64(0)) { $0 + $1.sizeBytes }
        for candidate in index.values
            .filter({ !$0.pinned && $0.kind == .rolling })
            .sorted(by: { $0.lastAccessed < $1.lastAccessed })
        where total > preferences.quotaBytes {
            try? FileManager.default.removeItem(at: fileURL(candidate))
            index.removeValue(forKey: candidate.id)
            total -= candidate.sizeBytes
        }
    }

    private func enforceQuota() {
        var total = index.values.reduce(Int64(0)) { $0 + $1.sizeBytes }
        for candidate in index.values.sorted(by: { lhs, rhs in
            if lhs.pinned != rhs.pinned { return !lhs.pinned }
            return lhs.lastAccessed < rhs.lastAccessed
        }) where total > preferences.quotaBytes {
            try? FileManager.default.removeItem(at: fileURL(candidate))
            index.removeValue(forKey: candidate.id)
            total -= candidate.sizeBytes
        }
        persist()
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? JSONEncoder.uMusic.encode(index).write(to: indexURL, options: .atomic)
    }
}
