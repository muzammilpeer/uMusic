import SwiftUI
import UMusicCore

struct Sprint6LibraryScreen: View {
    let library: (any LibraryProviding)?
    let playback: (any PlaybackControlling)?
    let offline: (any OfflineManaging)?
    @State private var snapshot = LibrarySnapshot.empty
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if snapshot.tracks.isEmpty {
                ContentUnavailableView("Library not synced", systemImage: "music.note.list", description: Text("Choose Sync to cache your server library on this device."))
            } else {
                List(Array(snapshot.tracks.enumerated()), id: \.element.id) { index, track in
                    HStack {
                    Button { Task { await playback?.setQueue(snapshot.tracks, startingAt: index) } } label: {
                        VStack(alignment: .leading) {
                            Text(track.title)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if let offline {
                        Menu("Offline", systemImage: "arrow.down.circle") {
                            Button("Download") { Task { try? await offline.download(track, retention: .rolling) } }
                            Button("Download and Keep") { Task { try? await offline.download(track, retention: .pinned) } }
                            Button("Remove Download", role: .destructive) { Task { try? await offline.removeDownload(trackID: track.id) } }
                        }.labelStyle(.iconOnly)
                    }
                    }
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            Button("Sync", systemImage: "arrow.triangle.2.circlepath") { Task { await sync() } }
                .disabled(library == nil || snapshot.isSyncing)
        }
        .overlay { if snapshot.isSyncing { ProgressView("Syncing Library…") } }
        .alert("Library Sync Failed", isPresented: .constant(errorMessage != nil)) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
        .task {
            guard let library else { return }
            for await value in library.snapshots { snapshot = value }
        }
    }

    private func sync() async {
        do { try await library?.sync() }
        catch is CancellationError {}
        catch { errorMessage = "Your cached library is still available. Please try again." }
    }
}

struct NowScreen: View {
    let playback: (any PlaybackControlling)?
    let snapshot: PlaybackSnapshot
    let context: (any ContextManaging)?
    @State private var scrubPosition = 0.0
    @State private var isScrubbing = false
    @State private var showsVisualizer = false
    @State private var lowEnergyMode = true

    var body: some View {
        Group {
            if let track = snapshot.track {
                ScrollView {
                VStack(spacing: 24) {
                    RoundedRectangle(cornerRadius: 24).fill(.quaternary).aspectRatio(1, contentMode: .fit).overlay { Image(systemName: "music.note").font(.system(size: 72)).foregroundStyle(.secondary) }
                    VStack { Text(track.title).font(.title2.bold()).multilineTextAlignment(.center); Text(track.artist).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    Toggle("Visualizer", isOn: $showsVisualizer)
                    if showsVisualizer { PlaybackVisualizer(snapshot: snapshot, lowEnergyMode: lowEnergyMode, isVisible: true) }
                    Slider(value: $scrubPosition, in: 0...max(track.durationSeconds ?? 1, 1), onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing { Task { await playback?.seek(to: scrubPosition) } }
                    })
                    HStack(spacing: 28) {
                        Button("Back 15", systemImage: "gobackward.15") { Task { await playback?.skip(by: -15) } }.labelStyle(.iconOnly)
                        Button("Previous", systemImage: "backward.fill") { Task { await playback?.previous() } }.labelStyle(.iconOnly).disabled(!snapshot.canGoPrevious)
                        Button(snapshot.phase == .playing ? "Pause" : "Play", systemImage: snapshot.phase == .playing ? "pause.circle.fill" : "play.circle.fill") { Task { snapshot.phase == .playing ? await playback?.pause() : await playback?.play() } }.labelStyle(.iconOnly).controlSize(.extraLarge)
                        Button("Next", systemImage: "forward.fill") { Task { await playback?.next() } }.labelStyle(.iconOnly).disabled(!snapshot.canGoNext)
                        Button("Forward 15", systemImage: "goforward.15") { Task { await playback?.skip(by: 15) } }.labelStyle(.iconOnly)
                    }
                    .accessibilityElement(children: .contain)
                    if let failure = snapshot.failureMessage { Text(failure).foregroundStyle(.red).font(.callout) }
                    if !snapshot.queue.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Queue").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(Array(snapshot.queue.enumerated()), id: \.element.id) { offset, item in
                                HStack {
                                    Image(systemName: item.id == snapshot.currentQueueItemID ? "speaker.wave.2.fill" : item.origin == .manual ? "hand.tap" : "sparkles")
                                        .foregroundStyle(item.id == snapshot.currentQueueItemID ? UMusicTheme.accent : .secondary)
                                    VStack(alignment: .leading) { Text(item.track.title).lineLimit(1); Text(item.track.artist).font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    if item.id != snapshot.currentQueueItemID {
                                        Button("Move Up", systemImage: "chevron.up") { Task { await playback?.moveQueueItems(fromOffsets: IndexSet(integer: offset), toOffset: max(offset - 1, 0)) } }.labelStyle(.iconOnly).disabled(offset == 0)
                                        Button("Move Down", systemImage: "chevron.down") { Task { await playback?.moveQueueItems(fromOffsets: IndexSet(integer: offset), toOffset: min(offset + 2, snapshot.queue.count)) } }.labelStyle(.iconOnly).disabled(offset + 1 == snapshot.queue.count)
                                        Button("Remove", systemImage: "minus.circle") { Task { await playback?.removeQueueItem(id: item.id) } }.labelStyle(.iconOnly)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }.padding()
                }
            } else {
                ContentUnavailableView("Nothing Playing", systemImage: "play.circle", description: Text("Choose music from Library."))
            }
        }
        .navigationTitle("Now")
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: snapshot.positionSeconds) { _, value in if !isScrubbing { scrubPosition = value } }
        .task {
            guard let context else { lowEnergyMode = true; return }
            lowEnergyMode = await context.settings().lowEnergyMode
            for await settings in context.snapshots { lowEnergyMode = settings.lowEnergyMode }
        }
    }
}

struct MiniPlayer: View {
    let snapshot: PlaybackSnapshot
    let playback: any PlaybackControlling
    let showNow: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: showNow) {
                VStack(alignment: .leading) { Text(snapshot.track?.title ?? "").lineLimit(1); Text(snapshot.track?.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Button(snapshot.phase == .playing ? "Pause" : "Play", systemImage: snapshot.phase == .playing ? "pause.fill" : "play.fill") { Task { snapshot.phase == .playing ? await playback.pause() : await playback.play() } }.labelStyle(.iconOnly)
            Button("Next", systemImage: "forward.fill") { Task { await playback.next() } }.labelStyle(.iconOnly).disabled(!snapshot.canGoNext)
        }
        .padding(.horizontal).frame(minHeight: 58).background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

struct Sprint6SearchScreen: View {
    @State private var query = ""

    var body: some View {
        ContentUnavailableView.search(text: query)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Songs, artists, albums, and playlists")
    }
}
