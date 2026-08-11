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
    @State private var confirmsDownloadAll = false
    @State private var bulkDownloadProgress: BulkDownloadProgress?
    @State private var showsFilters = false

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
        .refreshable { await sync() }
        .navigationTitle(selectedFacet ?? sectionTitle)
        .searchable(text: $query, prompt: "Songs, artists, albums, genres")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup {
                Menu(sectionTitle, systemImage: "rectangle.grid.1x2") {
                    ForEach(LibrarySection.allCases, id: \.self) { value in Button(value.rawValue.capitalized) { section = value; selectedFacet = nil } }
                }
                Button {
                    showsFilters = true
                } label: {
                    Label("Filter", systemImage: language == nil && year == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                if offline != nil {
                    Button("Download All", systemImage: "arrow.down.circle") { confirmsDownloadAll = true }
                        .disabled(snapshot.tracks.isEmpty || bulkDownloadProgress != nil)
                }
                Button("Sync", systemImage: "arrow.triangle.2.circlepath") { Task { await sync() } }.disabled(library == nil || snapshot.isSyncing)
            }
        }
        .overlay {
            if let progress = bulkDownloadProgress {
                VStack(spacing: 12) {
                    if progress.isClearing {
                        ProgressView()
                        Text("Clearing existing downloads…")
                    } else {
                        ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                        Text("Downloading \(progress.completed) of \(progress.total)")
                    }
                }
                .font(.callout)
                .padding()
                .frame(maxWidth: 280)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: UMusicTheme.cornerRadius))
            } else if snapshot.isSyncing {
                ProgressView("Syncing Library…")
            }
        }
        .alert("Library Error", isPresented: .constant(errorMessage != nil)) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
        .sheet(isPresented: $showsFilters) {
            LibraryFilterSheet(tracks: snapshot.tracks, language: $language, year: $year)
        }
        .confirmationDialog("Download all songs?", isPresented: $confirmsDownloadAll) {
            Button("Replace All Downloads", role: .destructive) { Task { await downloadAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("uMusic will stop playback, remove every existing offline song, then download a fresh copy of the full synced library using parallel downloads. Library and learning data are not removed.")
        }
        .task {
            if let playlists { playlistSummaries = (try? await playlists.playlists()) ?? [] }
            guard let library else { return }
            await refreshFromCache(using: library)
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
    private func sync() async {
        do {
            guard let library else { return }
            try await library.sync()
            await refreshFromCache(using: library)
            await playback?.reconcileQueue(availableTracks: snapshot.tracks)
        } catch is CancellationError {
        } catch {
            errorMessage = "Your cached library is still available."
        }
    }

    private func refreshFromCache(using library: any LibraryProviding) async {
        do {
            let tracks = try await library.browse(.init())
            snapshot = .init(tracks: tracks, lastSyncAt: snapshot.lastSyncAt, isSyncing: false)
            if query.isEmpty { searchResults = tracks }
        } catch {
            errorMessage = "The local library could not be loaded."
        }
    }

    private func downloadAll() async {
        guard let offline else { return }
        let tracks = snapshot.tracks
        guard !tracks.isEmpty else { return }
        bulkDownloadProgress = .clearing(total: tracks.count)
        do {
            await playback?.pause()
            try await offline.removeAllDownloads()
            bulkDownloadProgress = .downloading(completed: 0, total: tracks.count)

            let workerCount = min(tracks.count, max(1, ProcessInfo.processInfo.activeProcessorCount))
            var nextIndex = 0
            var completed = 0
            var failures: [String] = []
            await withTaskGroup(of: String?.self) { group in
                func enqueueNext() {
                    guard nextIndex < tracks.count else { return }
                    let track = tracks[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        do {
                            try await offline.download(track, retention: .pinned)
                            return nil
                        } catch {
                            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                    }
                }

                for _ in 0..<workerCount { enqueueNext() }
                while let failure = await group.next() {
                    completed += 1
                    if let failure { failures.append(failure) }
                    bulkDownloadProgress = .downloading(completed: completed, total: tracks.count)
                    enqueueNext()
                }
            }
            bulkDownloadProgress = nil
            if !failures.isEmpty {
                let succeeded = tracks.count - failures.count
                errorMessage = "Downloaded \(succeeded) of \(tracks.count) songs. \(failures[0]) Choose Download All to retry a fresh download."
            }
        } catch is CancellationError {
            bulkDownloadProgress = nil
        } catch {
            bulkDownloadProgress = nil
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = "The existing downloads could not be cleared. \(detail)"
        }
    }
}

private struct LibraryFilterSheet: View {
    let tracks: [TrackSummary]
    @Binding var language: String?
    @Binding var year: Int?
    @Environment(\.dismiss) private var dismiss

    private var languages: [String] {
        Set(tracks.map { $0.language ?? "Unknown" }).sorted()
    }

    private var years: [Int] {
        Set(tracks.compactMap(\.releaseYear)).sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Language") {
                    selectionRow("All languages", selected: language == nil) { language = nil }
                    ForEach(languages, id: \.self) { value in
                        selectionRow(value, selected: language == value) { language = value }
                    }
                }
                Section("Release Year") {
                    selectionRow("All years", selected: year == nil) { year = nil }
                    ForEach(years, id: \.self) { value in
                        selectionRow(String(value), selected: year == value) { year = value }
                    }
                }
            }
            .navigationTitle("Library Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { language = nil; year = nil }
                        .disabled(language == nil && year == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func selectionRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct BulkDownloadProgress {
    let completed: Int
    let total: Int
    let isClearing: Bool

    static func clearing(total: Int) -> Self { .init(completed: 0, total: total, isClearing: true) }
    static func downloading(completed: Int, total: Int) -> Self { .init(completed: completed, total: total, isClearing: false) }
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
            .refreshable { if let offline { snapshot = await offline.storageSnapshot() } }
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
        .refreshable { await reload() }
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
    @Binding var searchPresented: Bool
    let library: (any LibraryProviding)?; let playback: (any PlaybackControlling)?; let offline: (any OfflineManaging)?; let playlists: (any PlaylistManaging)?
    @State private var results: [TrackSummary] = []
    @State private var playlistSummaries: [PlaylistSummary] = []
    var body: some View {
        Group {
            if query.isEmpty { ContentUnavailableView("Search your cached library", systemImage: "magnifyingglass") }
            else { TrackListView(tracks: results, playback: playback, offline: offline, playlists: playlists, playlistSummaries: playlistSummaries) }
        }
        .navigationTitle("Search").searchable(text: $query, isPresented: $searchPresented, prompt: "Songs, artists, albums, genres")
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await refresh() }
        .task { playlistSummaries = (try? await playlists?.playlists()) ?? [] }
        .task(id: query) {
            do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation(); results = try await library?.browse(.init(text: query)) ?? [] }
            catch is CancellationError {} catch { results = [] }
        }
    }

    private func refresh() async {
        do {
            try await library?.sync()
            results = try await library?.browse(.init(text: query)) ?? []
            playlistSummaries = (try? await playlists?.playlists()) ?? []
        } catch is CancellationError {
        } catch {
            results = (try? await library?.browse(.init(text: query))) ?? results
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
