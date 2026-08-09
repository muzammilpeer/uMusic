import Foundation

enum AppConfiguration {
    static let productionServer = URL(string: "https://umusic.muzammilpeer.uk/")!
}

enum AppEnergyPolicy {
    private static let key = "uMusicLowEnergyMode"

    static var lowEnergyEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: key) != nil else { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

struct ArtistSummary: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
}

struct AlbumSummary: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let title: String
}

struct Track: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let artist: ArtistSummary
    let album: AlbumSummary?
    let durationMS: Int
    let genres: [String]
    let energy: Double?
    let streamPath: String
    var streamURL: URL? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, genres, energy
        case durationMS = "duration_ms"
        case streamPath = "stream_path"
        case streamURL = "stream_url"
    }

    var durationText: String {
        let seconds = durationMS / 1_000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct Page<Element: Codable & Sendable>: Codable, Sendable {
    let count: Int
    let next: URL?
    let previous: URL?
    let results: [Element]
}

struct Playlist: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let description: String
    let tracks: [PlaylistTrack]
    let revision: Int?
    let role: String?
    let owner: String?
}

struct PlaylistTrack: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let artist: String
}

struct PlaylistInvitation: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let playlistID: UUID
    let playlistName: String
    let invitedBy: String?
    let role: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id, role
        case playlistID = "playlist_id"
        case playlistName = "playlist_name"
        case invitedBy = "invited_by"
        case expiresAt = "expires_at"
    }
}

struct PlaylistMember: Codable, Hashable, Identifiable, Sendable {
    let userID: Int
    let username: String
    let role: String
    var id: Int { userID }

    enum CodingKeys: String, CodingKey {
        case username, role
        case userID = "user_id"
    }
}

struct Device: Codable, Sendable {
    let id: UUID
    let name: String
    let platform: String
    let scopes: [String]
    let revoked: Bool
}

struct LoginResponse: Codable, Sendable {
    let token: String
    let device: Device
}

struct CurrentSessionResponse: Codable, Sendable {
    let id: Int
    let username: String
    let device: Device
}

struct RemoteImportJob: Codable, Identifiable, Sendable {
    let id: UUID
    let adapter: String
    let status: String
    let importedCount: Int
    let error: String
    let items: [RemoteImportItem]

    enum CodingKeys: String, CodingKey {
        case id, adapter, status, error, items
        case importedCount = "imported_count"
    }

    var finished: Bool { ["completed", "partial", "failed"].contains(status) }
}

struct RemoteImportItem: Codable, Identifiable, Sendable {
    let id: UUID
    let position: Int
    let kind: String
    let sourceHost: String
    let status: String
    let imported: Bool
    let error: String

    enum CodingKeys: String, CodingKey {
        case id, position, kind, status, imported, error
        case sourceHost = "source_host"
    }
}

struct ListeningEvent: Codable, Sendable {
    let clientEventID: UUID
    let playbackID: UUID
    let trackID: UUID
    let eventType: String
    let clientTimestamp: Date
    let positionMS: Int
    let durationMS: Int
    let listenedMSDelta: Int
    let offline: Bool
    var contextSnapshotID: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case clientEventID = "client_event_id"
        case playbackID = "playback_id"
        case trackID = "track_id"
        case eventType = "event_type"
        case clientTimestamp = "client_timestamp"
        case positionMS = "position_ms"
        case durationMS = "duration_ms"
        case listenedMSDelta = "listened_ms_delta"
        case offline
        case contextSnapshotID = "context_snapshot_id"
    }
}

struct EventBatch: Codable, Sendable { let events: [ListeningEvent] }

extension JSONDecoder {
    static let uMusic: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    static let uMusic: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
