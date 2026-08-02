import Foundation

struct DeviceLoginResponse: Codable {
    let token: String
    let device: DeviceFixture
}

struct DeviceFixture: Codable, Identifiable {
    let id: UUID
    let name: String
    let platform: String
    let scopes: [String]
    let revoked: Bool
    let createdAt: Date
}

struct SyncManifestFixture: Codable, Identifiable {
    let id: UUID
    let version: Int
    let playlistId: UUID
    let entries: [ManifestEntryFixture]
}

struct ManifestEntryFixture: Codable {
    let trackId: UUID
    let position: Int
    let title: String
    let sizeBytes: Int64
    let sha256: String
    let metadataVersion: Int64
    let artworkChecksum: String?
    let downloadUrl: URL
    let downloadExpiresAt: Date
}
