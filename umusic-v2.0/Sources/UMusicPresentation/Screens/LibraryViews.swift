import SwiftUI
import UMusicCore

struct LibraryScreen: View {
    let library: (any LibraryProviding)?
    let playback: (any PlaybackControlling)?
    let offline: (any OfflineManaging)?
    let playlists: (any PlaylistManaging)?
    @State private var snapshot = LibrarySnapshot.empty
    @State private var searchResults: [TrackSummary] = []
    @State private var section: LibrarySection = .songs
    @State private var query = ""
    @State private var selectedFacet: String?
    @State private var language: String?
    @State private var year: Int?
    @State private var playlistSummaries: [PlaylistSummary] = []
    @State private var errorMessage: String?

    private var sourceTracks: [TrackSummary] { query.isEmpty ? snapshot.tracks : searchResults }
    private var filteredTracks: [TrackSummary] {
        sourceTracks.filter { track in
            (language == nil || (track.language ?? "Unknown") == language) &&
            (year == nil || track.releaseYear == year) && facetMatches(track)
        }
    }

    var body: some View {
        Group {
            if snapshot.tracks.isEmpty && !snapshot.isSyncing {
                ContentUnavailableView("Library not synced", systemImage: "music.note.list", description: Text("Choose Sync to cache your server library on this device."))
            } else if section == .playlists {
                PlaylistBrowser(playlists: playlists, playback: playback, offline: offline)
            } else if section == .downloaded {
                DownloadedTracksView(offline: offline, playback: playback)
            } else if section == .songs || selectedFacet != nil {
                TrackListView(tracks: filteredTracks, playback: playback, offline: offline, playlists: playlists, playlistSummaries: playlistSummaries)
            } else {
                facetList
            }
        }
        .navigationTitle(selectedFacet ?? sectionTitle)
        .searchable(text: $query, prompt: "Songs, artists, albums, genres")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup {
                Menu(sectionTitle, systemImage: "rectangle.grid.1x2") {
                    ForEach(LibrarySection.allCases, id: \.self) { value in Button(value.rawValue.capitalized) { section = value; selectedFacet = nil } }
                }
                Menu("Filter", systemImage: "line.3.horizontal.decrease.circle") {
                    Button("All languages") { language = nil }
                    ForEach(Set(snapshot.tracks.map { $0.language ?? "Unknown" }).sorted(), id: \.self) { value in Button(value) { language = value } }
                    Divider()
                    Button("All years") { year = nil }
                    ForEach(Set(snapshot.tracks.compactMap(\.releaseYear)).sorted(by: >), id: \.self) { value in Button(String(value)) { year = value } }
                }
                Button("Sync", systemImage: "arrow.triangle.2.circlepath") { Task { await sync() } }.disabled(library == nil || snapshot.isSyncing)
            }
        }
        .overlay { if snapshot.isSyncing { ProgressView("Syncing Library…") } }
        .alert("Library Error", isPresented: .constant(errorMessage != nil)) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
        .task {
            if let playlists { playlistSummaries = (try? await playlists.playlists()) ?? [] }
            guard let library else { return }
            for await value in library.snapshots { snapshot = value; if query.isEmpty { searchResults = value.tracks } }
        }
        .task(id: query) {
            guard let library else { return }
            do {
                try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation()
                searchResults = try await library.browse(.init(text: query))
            } catch is CancellationError {} catch { errorMessage = "Cached search could not be completed." }
        }
    }

    private var sectionTitle: String { section.rawValue.capitalized }
    private var facets: [(String, Int)] {
        let values: [String]
        switch section {
        case .albums: values = sourceTracks.map { $0.album ?? "Unknown Album" }
        case .artists: values = sourceTracks.map { $0.artist.isEmpty ? "Unknown Artist" : $0.artist }
        case .genres: values = sourceTracks.flatMap { ($0.genres?.isEmpty == false ? $0.genres! : ["Unknown Genre"]) }
        case .era: values = sourceTracks.map { $0.releaseYear.map(String.init) ?? "Unknown Year" }
        default: values = []
        }
        return Dictionary(grouping: values, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }
    private var facetList: some View {
        List(facets, id: \.0) { value, count in
            Button { selectedFacet = value } label: { HStack { Text(value); Spacer(); Text("\(count)").foregroundStyle(.secondary) } }
                .accessibilityLabel("\(value), \(count) songs")
        }
    }
    private func facetMatches(_ track: TrackSummary) -> Bool {
        guard let selectedFacet else { return true }
        switch section {
        case .albums: return (track.album ?? "Unknown Album") == selectedFacet
        case .artists: return (track.artist.isEmpty ? "Unknown Artist" : track.artist) == selectedFacet
        case .genres: return (track.genres?.isEmpty == false ? track.genres! : ["Unknown Genre"]).contains(selectedFacet)
        case .era: return (track.releaseYear.map(String.init) ?? "Unknown Year") == selectedFacet
        default: return true
        }
    }
    private func sync() async { do { try await library?.sync() } catch is CancellationError {} catch { errorMessage = "Your cached library is still available." } }
}

struct TrackListView: View {
    let tracks: [TrackSummary]
    let playback: (any PlaybackControlling)?
    let offline: (any OfflineManaging)?
    let playlists: (any PlaylistManaging)?
    let playlistSummaries: [PlaylistSummary]
    var body: some View {
        if tracks.isEmpty { ContentUnavailableView("No matching music", systemImage: "music.note") }
        else {
            List(Array(tracks.enumerated()), id: \.element.id) { index, track in
                HStack {
                    Button { Task { await playback?.setQueue(tracks, startingAt: index) } } label: {
                        VStack(alignment: .leading) { Text(track.title); Text(track.artist).font(.caption).foregroundStyle(.secondary); if let album = track.album { Text(album).font(.caption2).foregroundStyle(.tertiary) } }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    TrackActionsMenu(track: track, playback: playback, offline: offline, playlists: playlists, playlistSummaries: playlistSummaries)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(track.title), by \(track.artist)")
            }
        }
    }
}

private struct TrackActionsMenu: View {
    let track: TrackSummary
    let playback: (any PlaybackControlling)?
    let offline: (any OfflineManaging)?
    let playlists: (any PlaylistManaging)?
    let playlistSummaries: [PlaylistSummary]
    var body: some View {
        Menu("Actions for \(track.title)", systemImage: "ellipsis.circle") {
            Button("Play Now", systemImage: "play.fill") { Task { await playback?.setQueue([track], startingAt: 0) } }
            Button("Play Next", systemImage: "text.insert") { Task { await playback?.enqueue(track, placement: .next, origin: .manual) } }
            Button("Add to Queue", systemImage: "text.append") { Task { await playback?.enqueue(track, placement: .later, origin: .manual) } }
            if let offline {
                Divider(); Button("Download", systemImage: "arrow.down.circle") { Task { try? await offline.download(track, retention: .rolling) } }
                Button("Download and Keep", systemImage: "pin") { Task { try? await offline.download(track, retention: .pinned) } }
                Button("Remove Download", systemImage: "trash", role: .destructive) { Task { try? await offline.removeDownload(trackID: track.id) } }
            }
            if let playlists, !playlistSummaries.isEmpty {
                Menu("Add to Playlist") {
                    ForEach(playlistSummaries) { summary in Button(summary.name) { Task {
                        do { _ = try await playlists.addTrack(track, to: summary.id, expectedRevision: summary.revision) }
                        catch { if let latest = try? await playlists.playlist(id: summary.id) { _ = try? await playlists.addTrack(track, to: summary.id, expectedRevision: latest.revision) } }
                    } } }
                }
            }
        }.labelStyle(.iconOnly).accessibilityLabel("Actions for \(track.title)")
    }
}

private struct DownloadedTracksView: View {
    let offline: (any OfflineManaging)?; let playback: (any PlaybackControlling)?
    @State private var snapshot = OfflineStorageSnapshot(usedBytes: 0, quotaBytes: 0)
    var tracks: [TrackSummary] { snapshot.entries.map { TrackSummary(id: $0.trackID, title: $0.title, artist: $0.artist) } }
    var body: some View {
        TrackListView(tracks: tracks, playback: playback, offline: offline, playlists: nil, playlistSummaries: [])
            .task { if let offline { snapshot = await offline.storageSnapshot() } }
    }
}

struct PlaylistBrowser: View {
    let playlists: (any PlaylistManaging)?; let playback: (any PlaybackControlling)?; let offline: (any OfflineManaging)?
    @State private var summaries: [PlaylistSummary] = []
    @State private var selected: ManualPlaylist?
    @State private var newName = ""
    @State private var renameName = ""
    @State private var errorMessage: String?
    var body: some View {
        Group {
            if let selected {
                VStack {
                    List(Array(selected.tracks.enumerated()), id: \.offset) { index, track in
                        HStack {
                            Button { Task { await playback?.setQueue(selected.tracks, startingAt: index) } } label: { VStack(alignment: .leading) { Text(track.title); Text(track.artist).font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain)
                            Spacer(); Button("Remove from playlist", systemImage: "minus.circle") { Task { await removeTrack(index, from: selected) } }.labelStyle(.iconOnly)
                        }.accessibilityLabel("\(track.title), by \(track.artist)")
                    }
                    HStack { TextField("Playlist name", text: $renameName); Button("Rename") { Task { await rename(selected) } } }
                        .padding(.horizontal)
                    HStack { Button("Back") { self.selected = nil }; Spacer(); Button("Delete Playlist", role: .destructive) { Task { await delete(selected) } } }
                        .padding()
                }
            } else {
                List {
                    Section { HStack { TextField("New playlist", text: $newName); Button("Create") { Task { await create() } }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
                    Section("Playlists") {
                        if summaries.isEmpty { Text("No playlists") }
                        ForEach(summaries) { summary in Button { Task { selected = try? await playlists?.playlist(id: summary.id); renameName = selected?.name ?? "" } } label: { HStack { Text(summary.name); Spacer(); Text("\(summary.trackCount)").foregroundStyle(.secondary) } } }
                    }
                }
            }
        }
        .task { await reload() }
        .alert("Playlist Conflict", isPresented: .constant(errorMessage != nil)) { Button("Reload") { errorMessage = nil; Task { await reload() } } } message: { Text(errorMessage ?? "") }
    }
    private func reload() async { summaries = (try? await playlists?.playlists()) ?? [] }
    private func create() async { do { _ = try await playlists?.createPlaylist(name: newName); newName = ""; await reload() } catch { errorMessage = "The playlist could not be created." } }
    private func rename(_ value: ManualPlaylist) async { do { selected = try await playlists?.renamePlaylist(id: value.id, name: renameName, expectedRevision: value.revision); await reload() } catch { errorMessage = "The playlist changed elsewhere. Reload before renaming." } }
    private func removeTrack(_ index: Int, from value: ManualPlaylist) async { do { selected = try await playlists?.removeTrack(at: index, from: value.id, expectedRevision: value.revision); await reload() } catch { errorMessage = "The playlist changed elsewhere. Reload before removing the song." } }
    private func delete(_ value: ManualPlaylist) async { do { try await playlists?.deletePlaylist(id: value.id, expectedRevision: value.revision); selected = nil; await reload() } catch { errorMessage = "The playlist changed elsewhere. Reload before deleting." } }
}

struct SearchScreen: View {
    @Binding var query: String
    let library: (any LibraryProviding)?; let playback: (any PlaybackControlling)?; let offline: (any OfflineManaging)?; let playlists: (any PlaylistManaging)?
    @State private var results: [TrackSummary] = []
    @State private var playlistSummaries: [PlaylistSummary] = []
    var body: some View {
        Group {
            if query.isEmpty { ContentUnavailableView("Search your cached library", systemImage: "magnifyingglass") }
            else { TrackListView(tracks: results, playback: playback, offline: offline, playlists: playlists, playlistSummaries: playlistSummaries) }
        }
        .navigationTitle("Search").searchable(text: $query, prompt: "Songs, artists, albums, genres")
        .scrollDismissesKeyboard(.interactively)
        .task { playlistSummaries = (try? await playlists?.playlists()) ?? [] }
        .task(id: query) {
            do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation(); results = try await library?.browse(.init(text: query)) ?? [] }
            catch is CancellationError {} catch { results = [] }
        }
    }
}

struct DeepLinkDestination: View {
    let route: AppRoute; let library: (any LibraryProviding)?; let playback: (any PlaybackControlling)?; let offline: (any OfflineManaging)?; let playlists: (any PlaylistManaging)?
    @State private var tracks: [TrackSummary] = []
    @State private var playlist: ManualPlaylist?
    var body: some View {
        Group {
            switch route {
            case .track(let id): TrackListView(tracks: tracks.filter { $0.id == id }, playback: playback, offline: offline, playlists: playlists, playlistSummaries: [])
            case .playlist: TrackListView(tracks: playlist?.tracks ?? [], playback: playback, offline: offline, playlists: playlists, playlistSummaries: [])
            default: ContentUnavailableView("Link unavailable", systemImage: "link")
            }
        }
        .task {
            tracks = (try? await library?.browse(.init())) ?? []
            if case .playlist(let id) = route { playlist = try? await playlists?.playlist(id: id) }
        }
    }
}
