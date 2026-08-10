import Foundation
import UMusicDomain

public actor FilePlaylistStore: PlaylistManaging {
    private let url: URL
    private var values: [UUID: ManualPlaylist]

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([ManualPlaylist].self, from: data) {
            values = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        } else { values = [:] }
    }

    public func playlists() async throws -> [PlaylistSummary] {
        values.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { PlaylistSummary(id: $0.id, name: $0.name, trackCount: $0.tracks.count, automaticallyGrows: $0.automaticallyGrows, revision: $0.revision) }
    }

    public func playlist(id: UUID) async throws -> ManualPlaylist {
        guard let value = values[id] else { throw PlaylistStoreError.notFound }
        return value
    }

    public func createPlaylist(name: String) async throws -> ManualPlaylist {
        let clean = try validated(name)
        let value = ManualPlaylist(name: clean)
        values[value.id] = value; try persist(); return value
    }

    public func renamePlaylist(id: UUID, name: String, expectedRevision: Int64) async throws -> ManualPlaylist {
        let current = try checked(id, expectedRevision: expectedRevision)
        let value = ManualPlaylist(id: current.id, name: try validated(name), revision: current.revision + 1, automaticallyGrows: current.automaticallyGrows, tracks: current.tracks)
        values[id] = value; try persist(); return value
    }

    public func deletePlaylist(id: UUID, expectedRevision: Int64) async throws {
        _ = try checked(id, expectedRevision: expectedRevision)
        values.removeValue(forKey: id); try persist()
    }

    public func addTrack(_ track: TrackSummary, to playlistID: UUID, expectedRevision: Int64) async throws -> ManualPlaylist {
        let current = try checked(playlistID, expectedRevision: expectedRevision)
        let value = ManualPlaylist(id: current.id, name: current.name, revision: current.revision + 1, automaticallyGrows: current.automaticallyGrows, tracks: current.tracks + [track])
        values[playlistID] = value; try persist(); return value
    }

    public func removeTrack(at index: Int, from playlistID: UUID, expectedRevision: Int64) async throws -> ManualPlaylist {
        let current = try checked(playlistID, expectedRevision: expectedRevision)
        guard current.tracks.indices.contains(index) else { throw PlaylistStoreError.invalidIndex }
        var tracks = current.tracks; tracks.remove(at: index)
        let value = ManualPlaylist(id: current.id, name: current.name, revision: current.revision + 1, automaticallyGrows: current.automaticallyGrows, tracks: tracks)
        values[playlistID] = value; try persist(); return value
    }

    public func setAutomaticallyGrows(_ enabled: Bool, for playlistID: UUID, expectedRevision: Int64) async throws -> ManualPlaylist {
        let current = try checked(playlistID, expectedRevision: expectedRevision)
        let value = ManualPlaylist(id: current.id, name: current.name, revision: current.revision + 1, automaticallyGrows: enabled, tracks: current.tracks)
        values[playlistID] = value; try persist(); return value
    }

    private func checked(_ id: UUID, expectedRevision: Int64) throws -> ManualPlaylist {
        guard let value = values[id] else { throw PlaylistStoreError.notFound }
        guard value.revision == expectedRevision else { throw PlaylistStoreError.conflict }
        return value
    }

    private func validated(_ name: String) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 100 else { throw PlaylistStoreError.invalidName }
        return clean
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Array(values.values)).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
