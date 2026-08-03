import SwiftUI

@MainActor
final class OfflineViewModel: ObservableObject {
    @Published var activities: [ActivityOption] = []
    @Published var selectedActivity: UUID?
    @Published var preparing = false
    @Published var status = "No prepared session"
    @Published var tracks: [Track] = []
    @Published var entries: [ManifestEntry] = []
    @Published var cachedIDs: Set<UUID> = []
    @Published var syncingIDs: Set<UUID> = []
    @Published var allowCellularOnce = false
    @Published var cachedBytes: Int64 = 0
    @Published var deviceFreeBytes: Int64 = 0
    @Published var preferences = OfflinePreferences()

    let manager: OfflineManager
    private let api: any OfflineMusicAPI

    init(api: any OfflineMusicAPI = APIClient(), manager: OfflineManager = .shared) {
        self.api = api
        self.manager = manager
        if let data = UserDefaults.standard.data(forKey: "uMusicOfflinePreferences"),
           let saved = try? JSONDecoder.uMusic.decode(OfflinePreferences.self, from: data) {
            preferences = saved
        }
    }

    func load(server: URL, token: String) async {
        do {
            activities = try await api.activities(server: server, token: token)
            selectedActivity = selectedActivity ?? activities.first?.id
            if activities.isEmpty {
                status = "No activities are configured on the server."
            }
        } catch {
            activities = []
            selectedActivity = nil
            status = "Could not load activities: \(error.localizedDescription)"
        }
        tracks = QueueStore().load()
        await refreshCacheStatus()
    }

    func prepare(
        server: URL, token: String, deviceID: UUID, player: AudioPlayer, force: Bool = false
    ) async {
        guard let selectedActivity else { return }
        preparing = true
        defer { preparing = false }
        do {
            let generated = try await api.generateSession(
                server: server, token: token, activityID: selectedActivity,
                quotaBytes: preferences.quotaBytes, energy: 0.75
            )
            let plan = try await api.createSyncPlan(
                server: server, token: token, deviceID: deviceID, playlistID: generated.id
            )
            let manifest = try await api.manifest(server: server, token: token, planID: plan.id)
            await manager.updatePreferences(preferences)
            let result = await manager.prepare(manifest: manifest, force: force)
            try await api.acknowledge(
                server: server, token: token, planID: plan.id,
                downloaded: result.downloaded, failed: result.failed
            )
            tracks = manifest.entries.map(\.track)
            entries = manifest.entries
            await refreshCacheStatus()
            player.setPreparedQueue(tracks)
            player.configureOfflineURLs { [manager] trackID in
                await manager.localURL(for: trackID)
            }
            let playback = try await api.createPlaybackSession(
                server: server, token: token, trackIDs: tracks.map(\.id),
                contextSnapshotID: generated.contextSnapshotID
            )
            var recommendationID = generated.id
            player.configureContinuation(threshold: preferences.continuationThreshold) {
                [api, manager] existingIDs in
                guard let response = try? await api.continuation(
                    server: server, token: token, sessionID: playback.id,
                    recommendationID: recommendationID, existingTrackIDs: existingIDs,
                    desiredCount: 10
                ) else { return [] }
                recommendationID = response.recommendationVersionID
                await manager.prefetch(Array(response.tracks.dropFirst()))
                return response.tracks.map(\.track)
            }
            status = result.failed.isEmpty
                ? "Prepared \(tracks.count) tracks for offline playback"
                : "Prepared with \(result.failed.count) failed downloads"
        } catch {
            status = error.localizedDescription
        }
    }

    func syncTrack(_ track: Track) async {
        guard let entry = entries.first(where: { $0.trackID == track.id }) else {
            status = "Prepare a session first to create a fresh download link for this song."
            return
        }
        syncingIDs.insert(track.id)
        defer { syncingIDs.remove(track.id) }
        do {
            try await manager.sync(entry, force: true)
            await refreshCacheStatus()
            status = "Downloaded \(track.title)"
        } catch { status = error.localizedDescription }
    }

    func refreshCacheStatus() async {
        let cached = await manager.cachedTracks()
        cachedIDs = Set(cached.map(\.id))
        cachedBytes = await manager.cachedBytes()
        deviceFreeBytes = await manager.deviceFreeBytes()
    }

    func updateQuota(gigabytes: Double) async {
        preferences.quotaBytes = Int64(gigabytes * 1_024 * 1_024 * 1_024)
        if let data = try? JSONEncoder.uMusic.encode(preferences) {
            UserDefaults.standard.set(data, forKey: "uMusicOfflinePreferences")
        }
        await manager.updatePreferences(preferences)
        await refreshCacheStatus()
    }

    func removeDownload(_ track: Track) async {
        await manager.remove(track.id)
        await refreshCacheStatus()
        status = "Removed the offline copy of \(track.title). The server copy is unchanged."
    }

    func clearDownloads() async {
        await manager.clearAll()
        await refreshCacheStatus()
        status = "All offline music was removed from this device."
    }
}

struct OfflineView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: AudioPlayer
    @StateObject private var model = OfflineViewModel()
    @StateObject private var policy = DownloadPolicyMonitor()
    @State private var trackToDelete: Track?
    @State private var confirmingClearAll = false

    var body: some View {
        List {
            Section("Prepare a session") {
                Picker("Activity", selection: $model.selectedActivity) {
                    ForEach(model.activities) { activity in
                        Text(activity.name).tag(Optional(activity.id))
                    }
                }
                .disabled(model.activities.isEmpty)
                Text("Downloads the best activity-matched songs that fit within your offline music limit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #if os(macOS)
                Toggle("Wi-Fi or Ethernet only", isOn: $model.preferences.wifiOnly)
                #else
                Toggle("Wi-Fi only", isOn: $model.preferences.wifiOnly)
                #endif
                Toggle("Only while charging", isOn: $model.preferences.chargingOnly)
                LabeledContent("Connection", value: policy.connectionName)
                Picker("Offline music limit", selection: quotaBinding) {
                    ForEach([0.1, 0.5, 1, 2, 5, 10, 20, 50], id: \.self) { size in
                        Text(size == 0.1 ? "100 MB" : size < 1 ? "500 MB" : "\(Int(size)) GB").tag(size)
                    }
                }
                if !policy.usesWiFi {
                    #if os(macOS)
                    Toggle("Allow this network for this sync", isOn: $model.allowCellularOnce)
                        .tint(.orange)
                    Text("Enable once when the Mac is using a connection other than Wi-Fi or Ethernet.")
                        .font(.caption).foregroundStyle(.secondary)
                    #else
                    Toggle("Allow mobile data for this sync", isOn: $model.allowCellularOnce)
                        .tint(.orange)
                    Text("Mobile data is used only after you explicitly enable this override.")
                        .font(.caption).foregroundStyle(.secondary)
                    #endif
                }
                Button(model.preparing ? "Preparing…" : "Download for offline playback") {
                    Task { await prepare(force: false) }
                }
                .disabled(model.preparing)
                Button("Full Resync", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await prepare(force: true) }
                }
                .disabled(model.preparing)
                if !syncAllowed {
                    Text("Waiting for the selected network or charging condition.")
                        .foregroundStyle(.orange)
                }
                Text(model.status).foregroundStyle(.secondary)
                LabeledContent(
                    "Offline music used",
                    value: ByteCountFormatter.string(fromByteCount: model.cachedBytes, countStyle: .file)
                )
                LabeledContent(
                    "Selected limit",
                    value: ByteCountFormatter.string(
                        fromByteCount: model.preferences.quotaBytes, countStyle: .file
                    )
                )
                ProgressView(
                    value: Double(model.cachedBytes),
                    total: Double(max(1, model.preferences.quotaBytes))
                )
                LabeledContent(
                    availableStorageLabel,
                    value: ByteCountFormatter.string(
                        fromByteCount: model.deviceFreeBytes, countStyle: .file
                    )
                )
                Button("Delete All Offline Music", systemImage: "trash", role: .destructive) {
                    confirmingClearAll = true
                }
                .disabled(model.cachedIDs.isEmpty)
            }
            Section("Songs and download status") {
                ForEach(model.tracks) { track in
                    HStack {
                        Button {
                            Task {
                                if let url = await model.manager.localURL(for: track.id) {
                                    player.playOffline(track, url: url, in: model.tracks)
                                } else {
                                    player.play(track, in: model.tracks)
                                }
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(track.title)
                                Text(track.artist.name).foregroundStyle(.secondary)
                                Label(
                                    model.cachedIDs.contains(track.id) ? "Downloaded" : "Online only",
                                    systemImage: model.cachedIDs.contains(track.id)
                                        ? "checkmark.circle.fill" : "icloud"
                                )
                                .font(.caption)
                                .foregroundStyle(model.cachedIDs.contains(track.id) ? .green : .orange)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Button {
                            Task {
                                guard syncAllowed else {
                                    model.status = policyBlockMessage
                                    return
                                }
                                await model.syncTrack(track)
                            }
                        } label: {
                            if model.syncingIDs.contains(track.id) {
                                ProgressView()
                            } else {
                                Image(systemName: model.cachedIDs.contains(track.id)
                                      ? "arrow.clockwise.circle" : "arrow.down.circle")
                            }
                        }
                        .disabled(
                            model.syncingIDs.contains(track.id)
                        )
                        if model.cachedIDs.contains(track.id) {
                            Button(role: .destructive) { trackToDelete = track } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete offline copy of \(track.title)")
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .navigationTitle("Offline")
        .task {
            guard let server = session.server, let token = session.token else { return }
            await model.load(server: server, token: token)
        }
        .confirmationDialog(
            "Delete offline copy?", isPresented: deleteTrackPresented,
            presenting: trackToDelete
        ) { track in
            Button("Delete \(track.title)", role: .destructive) {
                Task { await model.removeDownload(track) }
            }
        } message: { _ in
            Text("This removes only the MP3 stored on this device. It remains on your server.")
        }
        .confirmationDialog(
            "Delete all offline music?", isPresented: $confirmingClearAll
        ) {
            Button("Delete All Downloads", role: .destructive) {
                Task { await model.clearDownloads() }
            }
        } message: {
            Text("The server library is not affected.")
        }
    }

    private var syncAllowed: Bool {
        policy.networkAvailable
            && (!model.preferences.wifiOnly || policy.usesWiFi || model.allowCellularOnce)
            && (!model.preferences.chargingOnly || policy.isCharging)
    }

    private var policyBlockMessage: String {
        if !policy.networkAvailable { return "No network connection is available." }
        if model.preferences.wifiOnly && !policy.usesWiFi && !model.allowCellularOnce {
            #if os(macOS)
            return "This connection is not Wi-Fi or Ethernet. Enable the one-time network override."
            #else
            return "Wi-Fi is unavailable. Enable the one-time mobile-data override if desired."
            #endif
        }
        if model.preferences.chargingOnly && !policy.isCharging {
            return "Connect this device to power or turn off Only while charging."
        }
        return "Sync is waiting for its selected policy conditions."
    }

    private func prepare(force: Bool) async {
        guard syncAllowed else {
            model.status = policyBlockMessage
            return
        }
        guard model.selectedActivity != nil else {
            model.status = model.activities.isEmpty
                ? "No activities are available. Check the server connection and try again."
                : "Select an activity before preparing music."
            return
        }
        await session.refreshDeviceIdentity()
        guard let server = session.server, let token = session.token,
              let deviceID = session.deviceID else {
            model.status = "This device could not verify its registration. Sign in again."
            return
        }
        await model.prepare(
            server: server, token: token, deviceID: deviceID,
            player: player, force: force
        )
    }

    private var availableStorageLabel: String {
        #if os(macOS)
        "Available on Mac"
        #else
        "Available on iPhone"
        #endif
    }

    private var quotaBinding: Binding<Double> {
        Binding(
            get: { Double(model.preferences.quotaBytes) / 1_024 / 1_024 / 1_024 },
            set: { value in Task { await model.updateQuota(gigabytes: value) } }
        )
    }

    private var deleteTrackPresented: Binding<Bool> {
        Binding(
            get: { trackToDelete != nil },
            set: { if !$0 { trackToDelete = nil } }
        )
    }
}
