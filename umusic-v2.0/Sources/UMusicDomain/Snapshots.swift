import Foundation

public struct TrackSummary: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let artist: String
    public let durationSeconds: Double?
    public let album: String?
    public let genres: [String]?
    public let language: String?
    public let releaseYear: Int?
    public let revision: Int64?
    public let contentClassifications: [ContentClassification]?
    public let songFeatures: SongFeatureSnapshot?

    public init(id: UUID, title: String, artist: String, durationSeconds: Double? = nil, album: String? = nil, genres: [String]? = nil, language: String? = nil, releaseYear: Int? = nil, revision: Int64? = nil, contentClassifications: [ContentClassification]? = nil, songFeatures: SongFeatureSnapshot? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.durationSeconds = durationSeconds
        self.album = album; self.genres = genres; self.language = language
        self.releaseYear = releaseYear; self.revision = revision; self.contentClassifications = contentClassifications; self.songFeatures = songFeatures
    }
}

public enum PlaybackPhase: String, Codable, Equatable, Sendable {
    case idle
    case preparing
    case paused
    case playing
    case buffering
    case interrupted
    case failed
}

public struct PlaybackSnapshot: Codable, Equatable, Sendable {
    public let phase: PlaybackPhase
    public let track: TrackSummary?
    public let positionSeconds: Double
    public let queueCount: Int
    public let canGoNext: Bool
    public let canGoPrevious: Bool
    public let failureMessage: String?
    public let queue: [QueueItem]
    public let currentQueueItemID: UUID?

    public init(
        phase: PlaybackPhase,
        track: TrackSummary?,
        positionSeconds: Double,
        queueCount: Int,
        canGoNext: Bool = false,
        canGoPrevious: Bool = false,
        failureMessage: String? = nil,
        queue: [QueueItem] = [],
        currentQueueItemID: UUID? = nil
    ) {
        self.phase = phase
        self.track = track
        self.positionSeconds = max(positionSeconds, 0)
        self.queueCount = max(queueCount, 0)
        self.canGoNext = canGoNext
        self.canGoPrevious = canGoPrevious
        self.failureMessage = failureMessage
        self.queue = queue
        self.currentQueueItemID = currentQueueItemID
    }

    public static let idle = PlaybackSnapshot(
        phase: .idle,
        track: nil,
        positionSeconds: 0,
        queueCount: 0
    )
}

public enum QueueItemOrigin: String, Codable, Equatable, Sendable { case manual, automatic }

public struct QueueItem: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let track: TrackSummary
    public let origin: QueueItemOrigin
    public init(id: UUID = UUID(), track: TrackSummary, origin: QueueItemOrigin) {
        self.id = id; self.track = track; self.origin = origin
    }
}

public enum PlaybackSourceIdentity: String, Codable, Equatable, Sendable { case cached, remote, unknown }

public struct DurableQueueSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let items: [QueueItem]
    public let currentIndex: Int
    public let positionSeconds: Double
    public let sourceIdentity: PlaybackSourceIdentity
    public let savedAt: Date

    public init(schemaVersion: Int = 1, items: [QueueItem], currentIndex: Int, positionSeconds: Double, sourceIdentity: PlaybackSourceIdentity, savedAt: Date = Date()) {
        self.schemaVersion = schemaVersion; self.items = items; self.currentIndex = currentIndex
        self.positionSeconds = max(positionSeconds, 0); self.sourceIdentity = sourceIdentity; self.savedAt = savedAt
    }
}

public enum PlaybackCommand: Sendable {
    case play, pause, next, previous
    case seek(seconds: Double)
    case skip(seconds: Double)
}

public enum PlaybackEngineEvent: Sendable {
    case ready(duration: Double?)
    case time(position: Double, duration: Double?)
    case playing
    case paused
    case ended
    case stalled
    case failed
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeOutputLost
}

public struct PlaybackTicket: Codable, Equatable, Sendable {
    public let trackID: UUID
    public let url: URL
    public let expiresAt: Date
    public let checksum: String
    public let bytes: Int64
    public let supportsRanges: Bool

    public init(trackID: UUID, url: URL, expiresAt: Date, checksum: String, bytes: Int64, supportsRanges: Bool) {
        self.trackID = trackID; self.url = url; self.expiresAt = expiresAt
        self.checksum = checksum; self.bytes = bytes; self.supportsRanges = supportsRanges
    }

    private enum CodingKeys: String, CodingKey {
        case trackID = "track_id"
        case url
        case expiresAt = "expires_at"
        case checksum
        case bytes
        case supportsRanges = "supports_ranges"
    }
}

public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public let tracks: [TrackSummary]
    public let lastSyncAt: Date?
    public let isSyncing: Bool

    public init(tracks: [TrackSummary], lastSyncAt: Date?, isSyncing: Bool) {
        self.tracks = tracks
        self.lastSyncAt = lastSyncAt
        self.isSyncing = isSyncing
    }

    public static let empty = LibrarySnapshot(tracks: [], lastSyncAt: nil, isSyncing: false)
}

public struct PlaylistSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let trackCount: Int
    public let automaticallyGrows: Bool
    public let revision: Int64

    public init(id: UUID, name: String, trackCount: Int, automaticallyGrows: Bool, revision: Int64 = 1) {
        self.id = id
        self.name = name
        self.trackCount = max(trackCount, 0)
        self.automaticallyGrows = automaticallyGrows
        self.revision = max(revision, 1)
    }
}

public struct ManualPlaylist: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let revision: Int64
    public let automaticallyGrows: Bool
    public let tracks: [TrackSummary]
    public init(id: UUID = UUID(), name: String, revision: Int64 = 1, automaticallyGrows: Bool = false, tracks: [TrackSummary] = []) {
        self.id = id; self.name = name; self.revision = max(revision, 1)
        self.automaticallyGrows = automaticallyGrows; self.tracks = tracks
    }
}

public enum PlaylistStoreError: Error, Equatable { case notFound, conflict, invalidName, invalidIndex }

public enum LibrarySection: String, CaseIterable, Codable, Sendable { case songs, albums, artists, genres, era, downloaded, playlists }
public struct LibraryQuery: Equatable, Sendable {
    public let text: String?
    public let artist: String?
    public let album: String?
    public let genre: String?
    public let releaseYear: Int?
    public let language: String?
    public init(text: String? = nil, artist: String? = nil, album: String? = nil, genre: String? = nil, releaseYear: Int? = nil, language: String? = nil) {
        self.text = text; self.artist = artist; self.album = album; self.genre = genre
        self.releaseYear = releaseYear; self.language = language
    }
}

public struct OfflineStorageSnapshot: Codable, Equatable, Sendable {
    public let usedBytes: Int64
    public let quotaBytes: Int64
    public let entries: [OfflineMediaEntry]
    public let allowsCellular: Bool
    public let activeDownloadCount: Int

    public init(usedBytes: Int64, quotaBytes: Int64, entries: [OfflineMediaEntry] = [], allowsCellular: Bool = false, activeDownloadCount: Int = 0) {
        self.usedBytes = max(usedBytes, 0)
        self.quotaBytes = max(quotaBytes, 0)
        self.entries = entries
        self.allowsCellular = allowsCellular
        self.activeDownloadCount = max(activeDownloadCount, 0)
    }
}

public enum OfflineRetention: String, Codable, Equatable, Sendable { case pinned, rolling }
public enum OfflineMediaState: String, Codable, Equatable, Sendable { case ready, downloading, failed }

public struct OfflineMediaEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { trackID }
    public let trackID: UUID
    public let title: String
    public let artist: String
    public let relativePath: String
    public let checksum: String
    public let bytes: Int64
    public let retention: OfflineRetention
    public let state: OfflineMediaState
    public let lastAccessedAt: Date
    public let predictedUtility: Double

    public init(trackID: UUID, title: String, artist: String, relativePath: String, checksum: String, bytes: Int64, retention: OfflineRetention, state: OfflineMediaState, lastAccessedAt: Date = Date(), predictedUtility: Double = 0) {
        self.trackID = trackID; self.title = title; self.artist = artist; self.relativePath = relativePath
        self.checksum = checksum; self.bytes = max(bytes, 0); self.retention = retention; self.state = state
        self.lastAccessedAt = lastAccessedAt; self.predictedUtility = predictedUtility
    }
}

public struct DiagnosticsSnapshot: Codable, Equatable, Sendable {
    public let frameworkVersion: String
    public let schemaVersion: Int
    public let buildIdentifier: String
    public let modelVersion: String
    public let featureSchemaVersion: String
    public let issues: [DiagnosticIssue]

    public init(frameworkVersion: String, schemaVersion: Int, buildIdentifier: String = "development", modelVersion: String = "uninstalled", featureSchemaVersion: String = "ranker-features-1", issues: [DiagnosticIssue] = []) {
        self.frameworkVersion = frameworkVersion
        self.schemaVersion = schemaVersion
        self.buildIdentifier = buildIdentifier
        self.modelVersion = modelVersion
        self.featureSchemaVersion = featureSchemaVersion
        self.issues = issues
    }
}

public struct DiagnosticIssue: Codable, Equatable, Sendable, Identifiable {
    public let code: String
    public let metadata: [String: String]
    public var id: String { code }
    public init(code: String, metadata: [String: String] = [:]) {
        let normalized = code.uppercased().map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" }
        self.code = String(normalized.prefix(64))
        self.metadata = DiagnosticRedaction.sanitize(metadata)
    }
}

public enum DiagnosticRedaction {
    public static let forbiddenKeys = ["token", "password", "url", "path", "coordinate", "latitude", "longitude", "health", "username"]
    public static func sanitize(_ metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [:]) { result, entry in
            let key = entry.key.lowercased()
            guard !forbiddenKeys.contains(where: key.contains) else { return }
            let value = entry.value
            guard !value.contains("://"), !value.hasPrefix("/"), value.utf8.count <= 128 else { return }
            result[entry.key] = value
        }
    }
}
