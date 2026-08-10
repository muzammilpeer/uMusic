import Foundation
import Testing
import UMusicData
import UMusicDomain

private func playlistURL() -> URL { FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json") }

@Test("Manual playlist CRUD persists and retains duplicate tracks")
func playlistCRUDAndRelaunch() async throws {
    let url = playlistURL(); defer { try? FileManager.default.removeItem(at: url) }
    let store = FilePlaylistStore(url: url)
    var playlist = try await store.createPlaylist(name: "  Running  ")
    #expect(playlist.name == "Running")
    let track = TrackSummary(id: UUID(), title: "Same title", artist: "Artist")
    playlist = try await store.addTrack(track, to: playlist.id, expectedRevision: playlist.revision)
    playlist = try await store.addTrack(track, to: playlist.id, expectedRevision: playlist.revision)
    #expect(playlist.tracks.count == 2)
    #expect(playlist.revision == 3)
    playlist = try await store.renamePlaylist(id: playlist.id, name: "Fast Running", expectedRevision: playlist.revision)
    playlist = try await store.removeTrack(at: 0, from: playlist.id, expectedRevision: playlist.revision)
    #expect(playlist.tracks == [track])

    let restored = FilePlaylistStore(url: url)
    #expect(try await restored.playlist(id: playlist.id) == playlist)
    try await restored.deletePlaylist(id: playlist.id, expectedRevision: playlist.revision)
    #expect(try await restored.playlists().isEmpty)
}

@Test("Stale playlist revisions are rejected without overwriting newer state")
func playlistOptimisticConflict() async throws {
    let url = playlistURL(); defer { try? FileManager.default.removeItem(at: url) }
    let store = FilePlaylistStore(url: url)
    let created = try await store.createPlaylist(name: "Focus")
    let updated = try await store.renamePlaylist(id: created.id, name: "Deep Focus", expectedRevision: created.revision)
    await #expect(throws: PlaylistStoreError.conflict) { try await store.renamePlaylist(id: created.id, name: "Stale", expectedRevision: created.revision) }
    #expect(try await store.playlist(id: created.id) == updated)
}

@Test("Playlist validation controls empty names and invalid item indexes")
func playlistValidation() async throws {
    let url = playlistURL(); defer { try? FileManager.default.removeItem(at: url) }
    let store = FilePlaylistStore(url: url)
    await #expect(throws: PlaylistStoreError.invalidName) { try await store.createPlaylist(name: "   ") }
    let playlist = try await store.createPlaylist(name: "Valid")
    await #expect(throws: PlaylistStoreError.invalidIndex) { try await store.removeTrack(at: 0, from: playlist.id, expectedRevision: playlist.revision) }
}
