import Foundation

struct ActivityOption: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let kind: String
}

struct GeneratedSession: Codable, Sendable {
    let id: UUID
    let contextSnapshotID: UUID?
    let tracks: [GeneratedTrack]

    enum CodingKeys: String, CodingKey {
        case id, tracks
        case contextSnapshotID = "context_snapshot_id"
    }
}

struct GeneratedTrack: Codable, Sendable {
    let position: Int
    let trackID: UUID
    let title: String
    let artist: String
    let durationMS: Int

    enum CodingKeys: String, CodingKey {
        case position, title, artist
        case trackID = "track_id"
        case durationMS = "duration_ms"
    }
}

struct SyncPlanResponse: Codable, Sendable { let id: UUID }

struct PlaybackSessionResponse: Codable, Sendable { let id: UUID }

struct ContinuationResponse: Codable, Sendable {
    let recommendationVersionID: UUID
    let tracks: [ManifestEntry]

    enum CodingKeys: String, CodingKey {
        case tracks
        case recommendationVersionID = "recommendation_version_id"
    }
}

struct SyncManifest: Codable, Sendable, Identifiable {
    let id: UUID
    let version: Int
    let playlistID: UUID
    let entries: [ManifestEntry]

    enum CodingKeys: String, CodingKey {
        case id, version, entries
        case playlistID = "playlist_id"
    }
}

struct ManifestEntry: Codable, Hashable, Identifiable, Sendable {
    var id: UUID { trackID }
    let trackID: UUID
    let position: Int
    let title: String
    let artist: ArtistSummary
    let album: AlbumSummary?
    let durationMS: Int
    let genres: [String]
    let energy: Double?
    let streamPath: String
    let sizeBytes: Int64
    let sha256: String
    let metadataVersion: Int64
    let artworkChecksum: String?
    let downloadURL: URL
    let downloadExpiresAt: Date

    enum CodingKeys: String, CodingKey {
        case position, title, artist, album, genres, energy, sha256
        case trackID = "track_id"
        case durationMS = "duration_ms"
        case streamPath = "stream_path"
        case sizeBytes = "size_bytes"
        case metadataVersion = "metadata_version"
        case artworkChecksum = "artwork_checksum"
        case downloadURL = "download_url"
        case downloadExpiresAt = "download_expires_at"
    }

    var track: Track {
        Track(
            id: trackID, title: title, artist: artist, album: album,
            durationMS: durationMS, genres: genres, energy: energy, streamPath: streamPath
        )
    }
}

struct CachedTrack: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case prepared, rolling }
    let id: UUID
    let title: String
    let sha256: String
    let sizeBytes: Int64
    let localFilename: String
    var pinned: Bool
    var lastAccessed: Date
    let kind: Kind
}

struct OfflinePreferences: Codable, Sendable {
    var wifiOnly = true
    var chargingOnly = false
    var quotaBytes: Int64 = 5 * 1_024 * 1_024 * 1_024
    var continuationThreshold = 3
}
