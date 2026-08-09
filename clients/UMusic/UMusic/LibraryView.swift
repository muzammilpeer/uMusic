import SwiftUI

private enum SidebarDestination: String, CaseIterable, Identifiable {
    case music, sharedInvites, downloads, activity, queue, importMusic, admin
    var id: Self { self }
}

struct LibraryView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: AudioPlayer
    @StateObject private var model: LibraryViewModel
    @State private var destination: SidebarDestination? = .music
    @State private var trackPendingServerDelete: Track?

    init(api: any MusicAPI) { _model = StateObject(wrappedValue: LibraryViewModel(api: api)) }

    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                Section("Music") {
                    NavigationLink(value: SidebarDestination.music) {
                        Label("Songs", systemImage: "music.note.list")
                    }
                    NavigationLink(value: SidebarDestination.downloads) {
                        Label("Sync & Downloads", systemImage: "arrow.down.circle")
                    }
                    NavigationLink(value: SidebarDestination.sharedInvites) {
                        Label("Shared Invitations", systemImage: "person.2.badge.plus")
                    }
                    NavigationLink(value: SidebarDestination.activity) {
                        Label("Activity", systemImage: "figure.run")
                    }
                    NavigationLink(value: SidebarDestination.queue) {
                        Label("Play Queue", systemImage: "list.number")
                    }
                }
                Section("Admin") {
                    NavigationLink(value: SidebarDestination.importMusic) {
                        Label("Import from URLs", systemImage: "link.badge.plus")
                    }
                    NavigationLink(value: SidebarDestination.admin) {
                        Label("Admin Options", systemImage: "gearshape.2")
                    }
                }
                Section("Account") {
                    Button(role: .destructive) { session.signOut() } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("uMusic")
        } detail: {
            destinationView
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if player.current != nil { MiniPlayerView() }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: model.query) {
            guard let server = session.server, let token = session.token else { return }
            model.scheduleSearch(server: server, token: token)
        }
        .onChange(of: model.authorizationRevoked) {
            if model.authorizationRevoked {
                session.signOut(message: APIError.unauthorized.localizedDescription)
            }
        }
        .task {
            guard let server = session.server, let token = session.token else { return }
            player.configure(server: server, token: token)
            await session.refreshDeviceIdentity()
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch destination ?? .music {
        case .music:
            musicLibrary
        case .downloads:
            OfflineView()
        case .sharedInvites:
            PlaylistInvitationsView()
        case .activity:
            WorkoutView()
        case .queue:
            QueueView(embedded: true)
        case .importMusic:
            URLImportView()
        case .admin:
            AdminOptionsView()
        }
    }

    private var musicLibrary: some View {
        NavigationStack {
            List {
                if !model.playlists.isEmpty {
                    Section("Playlists") {
                    ForEach(model.playlists) { playlist in
                        NavigationLink(value: playlist) {
                            HStack {
                                Label(playlist.name, systemImage: "music.note")
                                Spacer()
                                Text(playlist.role?.capitalized ?? "Owner")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                }
                Section("Songs") {
                    ForEach(model.tracks) { track in
                        Button {
                            player.play(track, in: model.tracks)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(track.title).font(.headline)
                                    Text(track.artist.name).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(track.durationText)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Remove from Library", systemImage: "trash", role: .destructive) {
                                trackPendingServerDelete = track
                            }
                        }
                    }
                }
            }
            .overlay { libraryOverlay }
            .navigationTitle("uMusic")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(model.loading ? "Syncing…" : "Sync", systemImage: "arrow.clockwise") {
                        Task { await reload() }
                    }
                    .disabled(model.loading)
                }
            }
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistView(playlist: playlist, libraryTracks: model.tracks)
            }
        }
        .searchable(text: $model.query, prompt: "Tracks, artists, albums")
        .confirmationDialog(
            "Remove song from your library?",
            isPresented: Binding(
                get: { trackPendingServerDelete != nil },
                set: { if !$0 { trackPendingServerDelete = nil } }
            ),
            presenting: trackPendingServerDelete
        ) { track in
            Button("Remove \(track.title)", role: .destructive) {
                guard let server = session.server, let token = session.token else { return }
                Task {
                    if await model.deleteFromServer(track, server: server, token: token) {
                        trackPendingServerDelete = nil
                    }
                }
            }
        } message: { track in
            Text("This removes the song from your private library. Shared server media and listening history remain intact.")
        }
    }

    @ViewBuilder
    private var libraryOverlay: some View {
        if model.loading {
            ProgressView()
        } else if let message = model.errorMessage {
            ContentUnavailableView(
                "Could Not Load Music",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        } else if model.tracks.isEmpty {
            if model.query.isEmpty {
                ContentUnavailableView(
                    "No Synced Library",
                    systemImage: "arrow.clockwise.circle",
                    description: Text("Press Sync to download the latest song list from your server.")
                )
            } else {
                ContentUnavailableView.search(text: model.query)
            }
        }
    }

    private func reload() async {
        guard let server = session.server, let token = session.token else { return }
        await model.load(server: server, token: token)
    }
}

struct PlaylistView: View {
    let playlist: Playlist
    let libraryTracks: [Track]
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var session: SessionStore
    @State private var items: [PlaylistTrack]
    @State private var revision: Int
    @State private var pendingRemoval: PlaylistTrack?
    @State private var message: String?

    init(playlist: Playlist, libraryTracks: [Track]) {
        self.playlist = playlist
        self.libraryTracks = libraryTracks
        _items = State(initialValue: playlist.tracks)
        _revision = State(initialValue: playlist.revision ?? 1)
    }

    var body: some View {
        List(items) { item in
            HStack {
                VStack(alignment: .leading) {
                    Text(item.title)
                    Text(item.artist).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Play", systemImage: "play.fill") {
                    if let track = libraryTracks.first(where: { $0.id == item.id }) {
                        player.play(track, in: libraryTracks)
                    } else if let server = session.server, let token = session.token {
                        Task {
                            do {
                                let track = try await APIClient().track(
                                    server: server, token: token, trackID: item.id
                                )
                                player.play(track, in: [track])
                            } catch { message = error.localizedDescription }
                        }
                    }
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if playlist.role == "owner" || playlist.role == "editor" {
                    Button("Remove", systemImage: "minus.circle", role: .destructive) {
                        pendingRemoval = item
                    }
                }
                if playlist.role != "owner" {
                    Button("Save", systemImage: "square.and.arrow.down") {
                        guard let server = session.server, let token = session.token else { return }
                        Task {
                            do {
                                try await APIClient().saveSharedTrack(
                                    server: server, token: token,
                                    playlistID: playlist.id, trackID: item.id
                                )
                                message = "Saved to My Library. Press Sync to refresh songs."
                            } catch { message = error.localizedDescription }
                        }
                    }.tint(.blue)
                }
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            if playlist.role != "owner" {
                Button("Leave", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    guard let server = session.server, let token = session.token else { return }
                    Task {
                        do {
                            try await APIClient().leavePlaylist(
                                server: server, token: token, playlistID: playlist.id
                            )
                            message = "You left this playlist. Press Sync to refresh."
                        } catch { message = error.localizedDescription }
                    }
                }
            }
        }
        .alert("Playlist", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("OK") { message = nil } } message: { Text(message ?? "") }
        .confirmationDialog(
            "Remove from playlist?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { item in
            Button("Remove \(item.title)", role: .destructive) {
                guard let server = session.server, let token = session.token else { return }
                Task {
                    let remaining = items.filter { $0.id != item.id }
                    if let updated = try? await APIClient().updatePlaylist(
                        server: server, token: token, playlistID: playlist.id,
                        trackIDs: remaining.map(\.id), revision: revision
                    ) {
                        items = updated.tracks
                        revision = updated.revision ?? revision + 1
                        pendingRemoval = nil
                    }
                }
            }
        } message: { _ in
            Text("This removes the song from this playlist only. The server MP3 remains available.")
        }
    }
}

struct PlaylistInvitationsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var invitations: [PlaylistInvitation] = []
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List(invitations) { invite in
                VStack(alignment: .leading, spacing: 6) {
                    Text(invite.playlistName).font(.headline)
                    Text("\(invite.invitedBy ?? "A user") invited you as \(invite.role).")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Accept") { respond(invite, accept: true) }
                            .buttonStyle(.borderedProminent)
                        Button("Decline", role: .destructive) { respond(invite, accept: false) }
                            .buttonStyle(.bordered)
                    }
                }.padding(.vertical, 4)
            }
            .overlay {
                if invitations.isEmpty {
                    ContentUnavailableView("No Invitations", systemImage: "person.2")
                }
            }
            .navigationTitle("Shared Invitations")
            .task { await load() }
            .refreshable { await load() }
            .alert("Sharing", isPresented: Binding(
                get: { message != nil }, set: { if !$0 { message = nil } }
            )) { Button("OK") { message = nil } } message: { Text(message ?? "") }
        }
    }

    private func load() async {
        guard let server = session.server, let token = session.token else { return }
        do { invitations = try await APIClient().playlistInvitations(server: server, token: token) }
        catch { message = error.localizedDescription }
    }

    private func respond(_ invitation: PlaylistInvitation, accept: Bool) {
        guard let server = session.server, let token = session.token else { return }
        Task {
            do {
                try await APIClient().respondToInvitation(
                    server: server, token: token, invitationID: invitation.id, accept: accept
                )
                invitations.removeAll { $0.id == invitation.id }
                message = accept ? "Playlist accepted. Press Sync in Songs." : "Invitation declined."
            } catch { message = error.localizedDescription }
        }
    }
}

struct QueueView: View {
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    var embedded = false

    var body: some View {
        NavigationStack {
            List(player.queue) { track in
                Button { player.play(track) } label: {
                    VStack(alignment: .leading) {
                        Text(track.title)
                        Text(track.artist.name).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
            .navigationTitle("Queue")
            .toolbar {
                if !embedded { Button("Done") { dismiss() } }
            }
        }
        .frame(minWidth: embedded ? nil : 360, minHeight: embedded ? nil : 420)
    }
}

@MainActor
private final class URLImportViewModel: ObservableObject {
    @Published var urls = ""
    @Published var attested = false
    @Published private(set) var job: RemoteImportJob?
    @Published private(set) var submitting = false
    @Published var message = "Paste one URL per line, or separate URLs with commas."

    private let api: any RemoteImportAPI
    init(api: any RemoteImportAPI) { self.api = api }

    var urlCount: Int {
        urls.split { $0 == "," || $0 == "\n" || $0 == "\r" }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.count
    }

    func submit(server: URL, token: String) async {
        guard urlCount > 0 else { message = "Add at least one URL."; return }
        guard attested else { message = "Confirm that you are allowed to download these files."; return }
        submitting = true
        defer { submitting = false }
        do {
            job = try await api.createRemoteImport(
                server: server, token: token, urls: urls, attested: attested
            )
            message = "Import queued. You can leave this screen while the server downloads it."
            await poll(server: server, token: token)
        } catch { message = error.localizedDescription }
    }

    private func poll(server: URL, token: String) async {
        guard let jobID = job?.id else { return }
        for attempt in 0..<120 {
            try? await Task.sleep(for: .seconds(attempt < 6 ? 2 : 5))
            guard !Task.isCancelled else { return }
            do {
                let update = try await api.remoteImport(server: server, token: token, jobID: jobID)
                job = update
                message = update.finished
                    ? "Import finished: \(update.importedCount) song(s) added."
                    : "Server is processing \(update.items.count) item(s)…"
                if update.finished { return }
            } catch { message = error.localizedDescription; return }
        }
        message = "Import is still running. Return later to refresh your library."
    }
}

private struct URLImportView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model: URLImportViewModel

    init(api: any RemoteImportAPI = APIClient()) {
        _model = StateObject(wrappedValue: URLImportViewModel(api: api))
    }

    var body: some View {
        Form {
            Section("Download music from URLs") {
                TextEditor(text: $model.urls)
                    .frame(minHeight: 130)
                    .overlay(alignment: .topLeading) {
                        if model.urls.isEmpty {
                            Text("https://youtu.be/…\nhttps://example.com/song.mp3")
                                .foregroundStyle(.tertiary).padding(8).allowsHitTesting(false)
                        }
                    }
                LabeledContent("Detected URLs", value: "\(model.urlCount)")
                Toggle(
                    "I confirm I am authorized to download and store this audio",
                    isOn: $model.attested
                )
                Button(model.submitting ? "Importing…" : "Send to server") {
                    guard let server = session.server, let token = session.token else { return }
                    Task { await model.submit(server: server, token: token) }
                }
                .disabled(model.submitting || model.urlCount == 0 || !model.attested)
                Text(model.message).foregroundStyle(.secondary)
            }
            if let job = model.job {
                Section("Import job") {
                    LabeledContent("Status", value: job.status.capitalized)
                    LabeledContent("Imported", value: "\(job.importedCount)")
                    ForEach(job.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.sourceHost).font(.headline)
                                Spacer()
                                Text(item.status.capitalized).foregroundStyle(.secondary)
                            }
                            Text(item.kind == "youtube" ? "YouTube" : "Direct MP3")
                                .font(.caption).foregroundStyle(.secondary)
                            if !item.error.isEmpty {
                                Text(item.error).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Import Music")
    }
}

private struct AdminOptionsView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Form {
            Section("Server administration") {
                if let server = session.server {
                    Link(destination: server.appending(path: "library/")) {
                        Label("Open Web Music Portal", systemImage: "safari")
                    }
                    Link(destination: server.appending(path: "admin/")) {
                        Label("Open Django Admin", systemImage: "person.badge.key")
                    }
                }
                Text("The web admin opens securely in your browser and may ask you to sign in again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Mobile admin tools") {
                Label("Import direct MP3 and YouTube URLs", systemImage: "link.badge.plus")
                Label("Prepare activity-aware offline music", systemImage: "arrow.down.circle")
                Label("Manage workout and location context", systemImage: "figure.run")
            }
            Section("Account") {
                Button("Logout", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    session.signOut()
                }
            }
        }
        .navigationTitle("Admin Options")
    }
}

struct MiniPlayerView: View {
    @EnvironmentObject private var player: AudioPlayer
    @State private var showingNowPlaying = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button { showingNowPlaying = true } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(
                                colors: [.accentColor, .accentColor.opacity(0.65)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 64, height: 64)
                            .overlay {
                                Image(systemName: "music.note")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(player.current?.title ?? "")
                                .font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.72)
                            Text(player.current?.artist.name ?? "")
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            if !player.isPlaying {
                                Text("Resume at \(compactTime(player.elapsed))")
                                    .font(.caption.weight(.medium)).foregroundStyle(.tint)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                .buttonStyle(.plain)
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title2)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Text(compactTime(player.elapsed))
                Slider(
                    value: Binding(
                        get: { min(player.elapsed, compactDuration) },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...compactDuration
                )
                .accessibilityLabel("Song position")
                Text(compactTime(compactDuration))
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            if let message = player.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 18))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
        .padding(.horizontal, 8).padding(.bottom, 4)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                if value.translation.height < -35 { showingNowPlaying = true }
            }
        )
        #if os(iOS)
        .fullScreenCover(isPresented: $showingNowPlaying) { NowPlayingView() }
        #else
        .sheet(isPresented: $showingNowPlaying) { NowPlayingView() }
        #endif
    }

    private var compactDuration: Double {
        max(1, Double(player.current?.durationMS ?? 1) / 1_000)
    }

    private func compactTime(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var health = HealthWorkoutService.shared
    @ObservedObject private var detector = ActivityDetectionService.shared
    @ObservedObject private var location = LocationContextService.shared
    @State private var search = ""
    @State private var showingActivity = false

    private var duration: Double { max(1, Double(player.current?.durationMS ?? 1) / 1_000) }
    private var activityLabel: String {
        health.active ? health.activityName : detector.detectedKind?.capitalized ?? "Not detected"
    }
    private var filteredQueue: [Track] {
        guard !search.isEmpty else { return [] }
        return player.queue.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || $0.artist.name.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: health.active ? "figure.run.circle.fill" : "music.note")
                        .font(.system(size: 76)).foregroundStyle(.tint)
                    VStack(spacing: 4) {
                        Text(player.current?.title ?? "Not Playing")
                            .font(.title.bold()).multilineTextAlignment(.center)
                        Text(player.current?.artist.name ?? "").foregroundStyle(.secondary)
                        Text(activityLabel).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                    }

                    if health.active {
                        Label("Workout session active", systemImage: "figure.run.circle.fill")
                            .font(.headline).foregroundStyle(.green)
                    } else {
                        Button("Start Workout Session", systemImage: "figure.run") {
                            showingActivity = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .accessibilityHint("Choose an activity and start Health and fitness tracking")
                    }

                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(get: { min(player.elapsed, duration) }, set: { player.seek(to: $0) }),
                            in: 0...duration
                        )
                        .accessibilityLabel("Song position")
                        HStack {
                            Text(time(player.elapsed))
                            Spacer()
                            Text("−\(time(max(0, duration - player.elapsed)))")
                        }
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }

                    HStack(spacing: 38) {
                        Button { player.previous() } label: { Image(systemName: "backward.fill") }
                        Button { player.seek(to: player.elapsed - 15) } label: {
                            Image(systemName: "gobackward.15")
                        }
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 58))
                        }
                        Button { player.seek(to: player.elapsed + 15) } label: {
                            Image(systemName: "goforward.15")
                        }
                        Button { player.next() } label: { Image(systemName: "forward.fill") }
                    }
                    .buttonStyle(.plain)

                    GroupBox("Audio Output") {
                        VStack(spacing: 12) {
                            HStack {
                                Label(player.audioRouteName, systemImage: "headphones")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                VolumeButton()
                            }
                            LabeledContent("Headset battery") {
                                Text(player.headsetBatteryStatus)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            Text("iOS does not provide headset battery percentages to third-party music apps.")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    GroupBox("Live Activity") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 12) {
                            stat("Activity", activityLabel, "figure.run")
                            stat("Heart Rate", health.heartRate.map { "\(Int($0)) bpm" } ?? "—", "heart.fill")
                            stat("Calories", "\(Int(health.activeCalories)) kcal", "flame.fill")
                            stat("Distance", distance(health.distanceMeters), "location.fill")
                            stat("Steps", "\(Int(health.steps))", "shoeprints.fill")
                            stat("Phase", health.active ? "Live" : "Ready", "waveform.path.ecg")
                        }
                    }

                    GroupBox("Device & Location") {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(player.audioRouteName, systemImage: "airpodspro")
                            Label(
                                location.location.map {
                                    String(format: "%.3f, %.3f", $0.coordinate.latitude, $0.coordinate.longitude)
                                } ?? "Location unavailable",
                                systemImage: "location.circle"
                            )
                            if let speed = location.location?.speed, speed >= 0 {
                                Label(String(format: "%.1f km/h", speed * 3.6), systemImage: "speedometer")
                            }
                            Label(
                                "Motion: \(detector.detectedKind?.capitalized ?? "waiting") (\(detector.confidence))",
                                systemImage: "iphone.gen3.motion"
                            )
                            Label(health.heartRateSource, systemImage: "heart.text.clipboard")
                            Text(health.heartRateStatus)
                                .font(.caption)
                                .foregroundStyle(
                                    health.heartRate == nil && health.active ? .orange : .secondary
                                )
                            if let sampleTime = health.lastHeartRateAt {
                                Text("Last heart-rate sample \(sampleTime.formatted(date: .omitted, time: .standard))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if health.active {
                        Button("End Workout", systemImage: "stop.circle", role: .destructive) {
                            Task {
                                await health.stop()
                                location.stopTracking()
                            }
                        }
                        .buttonStyle(.bordered).controlSize(.large)
                    }

                    GroupBox("Find in Queue") {
                        VStack {
                            TextField("Search song or artist", text: $search)
                                .textFieldStyle(.roundedBorder)
                            ForEach(filteredQueue.prefix(6)) { track in
                                Button { player.play(track) } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(track.title)
                                            Text(track.artist.name).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "play.fill")
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    if let message = player.errorMessage {
                        Text(message).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                }
                .padding(24)
                .frame(maxWidth: 720)
            }
            .navigationTitle("Now Playing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back", systemImage: "chevron.down") { dismiss() }
                }
            }
            .sheet(isPresented: $showingActivity) {
                NavigationStack { WorkoutView() }
            }
        }
        .frame(minWidth: 360, minHeight: 620)
    }

    private func time(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private func distance(_ meters: Double) -> String {
        meters >= 1_000 ? String(format: "%.2f km", meters / 1_000) : "\(Int(meters)) m"
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(.tint)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(10).background(.quaternary, in: .rect(cornerRadius: 10))
    }
}

private struct VolumeButton: View {
    @EnvironmentObject private var player: AudioPlayer
    @State private var showingVolume = false

    var body: some View {
        Button { showingVolume.toggle() } label: {
            Image(systemName: volumeIcon)
                .font(.title3).frame(width: 44, height: 44)
        }
        .accessibilityLabel("Volume \(Int(player.volume * 100)) percent")
        .popover(isPresented: $showingVolume, arrowEdge: .bottom) {
            VStack(spacing: 10) {
                Image(systemName: "speaker.wave.3.fill")
                Slider(
                    value: Binding(
                        get: { player.volume },
                        set: { player.setVolume($0) }
                    ),
                    in: 0...1
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 150, height: 36)
                .padding(.vertical, 58)
                .accessibilityLabel("Volume")
                Text("\(Int(player.volume * 100))%")
                    .font(.caption.monospacedDigit())
            }
            .padding(14)
            .frame(width: 80, height: 230)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var volumeIcon: String {
        if player.volume == 0 { return "speaker.slash.fill" }
        if player.volume < 0.34 { return "speaker.wave.1.fill" }
        if player.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
