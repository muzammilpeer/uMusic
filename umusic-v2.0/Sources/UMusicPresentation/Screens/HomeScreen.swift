import SwiftUI
import UMusicCore

struct HomeScreen: View {
    let library: (any LibraryProviding)?
    let playback: (any PlaybackControlling)?
    let offline: (any OfflineManaging)?
    let personalization: (any PersonalizationManaging)?
    let calendarPreferences: (any CalendarPreferenceManaging)?
    let playbackSnapshot: PlaybackSnapshot

    @State private var librarySnapshot = LibrarySnapshot.empty
    @State private var history: [ListeningHistoryDay] = []
    @State private var offlineSnapshot = OfflineStorageSnapshot(usedBytes: 0, quotaBytes: 500 * 1_024 * 1_024)
    @State private var isStarting = false
    @State private var errorMessage: String?
    @State private var suggestedPlaylist: ManualPlaylist?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: UMusicTheme.contentSpacing) {
                hero
                if let suggestedPlaylist { calendarSuggestion(suggestedPlaylist) }
                if playbackSnapshot.track != nil { resumeCard }
                statusCards
                starterMixes
                historySection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .animation(HomeMotionPolicy.animation(reduceMotion: reduceMotion), value: history.count)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Home")
        .task { await observeLibrary() }
        .task { await loadSupportingState() }
        .alert("Unable to Start Listening", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Build your taste")
                .font(.largeTitle.bold())
            Text("Start with your cached library. uMusic will adapt as it learns what you enjoy.")
                .foregroundStyle(.secondary)
            Button {
                Task { await startListening() }
            } label: {
                if isStarting { ProgressView() } else { Label("Start Listening", systemImage: "play.fill") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isStarting || librarySnapshot.tracks.isEmpty || playback == nil)
            .accessibilityHint("Creates a listening queue from music already on this device")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: UMusicTheme.cornerRadius))
    }

    private var resumeCard: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    Text(playbackSnapshot.track?.title ?? "")
                        .font(.headline).lineLimit(1)
                    Text(playbackSnapshot.track?.artist ?? "")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Resume", systemImage: "play.fill") { Task { await playback?.play() } }
                    .labelStyle(.iconOnly)
                    .accessibilityHint("Resumes the restored queue from its saved position")
            }
        } label: { Label("Continue Listening", systemImage: "clock.arrow.circlepath") }
    }

    private func calendarSuggestion(_ playlist: ManualPlaylist) -> some View {
        GroupBox("Calendar suggestion") {
            HStack {
                Text(playlist.name)
                Spacer()
                Button("Play") { Task { await play(playlist.tracks) } }
            }
        }
    }

    private var statusCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On This Device").font(.headline)
            HStack(spacing: 12) {
                statusCard(value: "\(librarySnapshot.tracks.count)", label: "Cached songs", icon: "music.note.list")
                statusCard(value: "\(offlineSnapshot.entries.filter { $0.state == .ready }.count)", label: "Downloaded", icon: "arrow.down.circle.fill")
            }
            if librarySnapshot.tracks.isEmpty {
                Label("Sync from Library when you are online. Home never syncs automatically.", systemImage: "wifi.slash")
                    .font(.callout).foregroundStyle(.secondary)
            } else if let date = librarySnapshot.lastSyncAt {
                Text("Library updated \(date, format: .relative(presentation: .named))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func statusCard(value: String, label: LocalizedStringKey, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(value, systemImage: icon).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: UMusicTheme.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    private var starterMixes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Starter Mixes").font(.headline)
            if librarySnapshot.tracks.isEmpty {
                Text("Starter mixes will appear after your first manual Library sync.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(HomeStarterMix.make(from: librarySnapshot.tracks)) { mix in
                            Button { Task { await play(mix.tracks) } } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(systemName: mix.icon).font(.title2)
                                    Text(mix.title).font(.headline).lineLimit(1)
                                    Text("\(mix.tracks.count) songs").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding().frame(width: 170, alignment: .leading)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: UMusicTheme.cornerRadius))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Starts this mix")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 10 Days").font(.headline)
            if history.isEmpty {
                ContentUnavailableView(
                    "No recent listening yet",
                    systemImage: "clock",
                    description: Text("Recent songs and activity categories will appear here. Precise locations are never shown.")
                )
            } else {
                ForEach(history) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            Button { Task { await playback?.setQueue([entry.track], startingAt: 0) } } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(entry.track.title).lineLimit(1)
                                        Text(entry.track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(entry.activity.displayName).font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    } header: {
                        Text(group.day, format: .dateTime.weekday(.wide).month().day())
                            .font(.subheadline.bold())
                    }
                }
            }
        }
    }

    private func observeLibrary() async {
        guard let library else { return }
        for await value in library.snapshots { librarySnapshot = value }
    }

    private func loadSupportingState() async {
        try? await calendarPreferences?.evaluateSmartPlaylists(at: Date(), calendar: .autoupdatingCurrent)
        if let offline { offlineSnapshot = await offline.storageSnapshot() }
        if let personalization {
            history = await personalization.recentHistory(lastCalendarDays: 10, now: Date(), calendar: .autoupdatingCurrent)
        }
        suggestedPlaylist = await calendarPreferences?.suggestedPlaylist(at: Date())
    }

    private func startListening() async {
        if let preferred = await calendarPreferences?.preferredPlaylist(at: Date()), !preferred.tracks.isEmpty {
            await play(preferred.tracks)
            return
        }
        guard let personalization else { await play(librarySnapshot.tracks); return }
        isStarting = true
        let offlineIDs = Set(offlineSnapshot.entries.filter { $0.state == .ready }.map(\.trackID))
        let result = await personalization.recommendations(from: librarySnapshot.tracks, at: Date(), offlineTrackIDs: offlineIDs, excluding: [], limit: 25)
        await play(result.items.map(\.track), automatic: true)
        isStarting = false
    }

    private func play(_ tracks: [TrackSummary], automatic: Bool = false) async {
        guard !tracks.isEmpty else {
            errorMessage = "No cached songs are available. Open Library and choose Sync when online."
            return
        }
        if automatic { await playback?.setAutomaticQueue(tracks, startingAt: 0) }
        else { await playback?.setQueue(tracks, startingAt: 0) }
    }
}

enum HomeMotionPolicy {
    static func animation(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeInOut(duration: 0.2) }
}

struct HomeStarterMix: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let tracks: [TrackSummary]

    static func make(from tracks: [TrackSummary]) -> [HomeStarterMix] {
        guard !tracks.isEmpty else { return [] }
        var mixes = [HomeStarterMix(id: "all", title: "All Music", icon: "shuffle", tracks: Array(tracks.prefix(25)))]
        if let genre = tracks.compactMap({ $0.genres?.first }).first {
            let matches = tracks.filter { $0.genres?.contains(where: { $0.caseInsensitiveCompare(genre) == .orderedSame }) == true }
            if !matches.isEmpty { mixes.append(.init(id: "genre-\(genre.lowercased())", title: genre, icon: "guitars", tracks: Array(matches.prefix(25)))) }
        }
        let dated = tracks.filter { $0.releaseYear != nil }.sorted { ($0.releaseYear ?? 0) > ($1.releaseYear ?? 0) }
        if !dated.isEmpty { mixes.append(.init(id: "recent-era", title: "Recent Eras", icon: "calendar", tracks: Array(dated.prefix(25)))) }
        return mixes
    }
}
