import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published var query = ""
    @Published var errorMessage: String?
    @Published private(set) var loading = false
    @Published private(set) var authorizationRevoked = false

    private let api: any MusicAPI
    private let defaults: UserDefaults
    private var syncedTracks: [Track] = []
    private var searchTask: Task<Void, Never>?

    init(api: any MusicAPI, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        syncedTracks = defaults.data(forKey: "uMusicLibraryTracks").flatMap {
            try? JSONDecoder.uMusic.decode([Track].self, from: $0)
        } ?? []
        tracks = syncedTracks
        playlists = defaults.data(forKey: "uMusicLibraryPlaylists").flatMap {
            try? JSONDecoder.uMusic.decode([Playlist].self, from: $0)
        } ?? []
    }

    func load(server: URL, token: String) async {
        loading = true
        defer { loading = false }
        do {
            async let trackPage = api.tracks(server: server, token: token, query: query)
            async let playlistList = api.playlists(server: server, token: token)
            syncedTracks = try await trackPage.results
            tracks = filteredTracks()
            playlists = try await playlistList
            defaults.set(try? JSONEncoder.uMusic.encode(syncedTracks), forKey: "uMusicLibraryTracks")
            defaults.set(try? JSONEncoder.uMusic.encode(playlists), forKey: "uMusicLibraryPlaylists")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            authorizationRevoked = error as? APIError == .unauthorized
        }
    }

    func scheduleSearch(server: URL, token: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            tracks = filteredTracks()
        }
    }

    func removeLocally(_ track: Track) {
        syncedTracks.removeAll { $0.id == track.id }
        tracks = filteredTracks()
        defaults.set(try? JSONEncoder.uMusic.encode(syncedTracks), forKey: "uMusicLibraryTracks")
    }

    func deleteFromServer(_ track: Track, server: URL, token: String) async -> Bool {
        do {
            try await api.deleteTrack(server: server, token: token, trackID: track.id)
            removeLocally(track)
            return true
        } catch {
            errorMessage = error.localizedDescription
            authorizationRevoked = error as? APIError == .unauthorized
            return false
        }
    }

    private func filteredTracks() -> [Track] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return syncedTracks }
        return syncedTracks.filter {
            $0.title.localizedCaseInsensitiveContains(value)
                || $0.artist.name.localizedCaseInsensitiveContains(value)
                || ($0.album?.title.localizedCaseInsensitiveContains(value) ?? false)
        }
    }
}
