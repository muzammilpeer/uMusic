import SwiftUI
import UMusicCore

public struct AppShellView: View {
    @State private var navigation = AppNavigationModel()
    @State private var showsAccount = false
    @State private var showsOffline = false
    @State private var showsAppearance = false
    @State private var showsLearning = false
    @State private var showsActivity = false
    @State private var showsCalendarPreferences = false
    @AppStorage(UMusicTheme.themeDefaultsKey) private var themeRawValue = UMusicThemePreference.system.rawValue
    @AppStorage(UMusicTheme.accentDefaultsKey) private var accentRawValue = UMusicAccent.violet.rawValue
    private let authentication: (any AuthenticationManaging)?
    private let library: (any LibraryProviding)?
    private let playback: (any PlaybackControlling)?
    private let offline: (any OfflineManaging)?
    private let playlists: (any PlaylistManaging)?
    private let personalization: (any PersonalizationManaging)?
    private let context: (any ContextManaging)?
    private let calendarPreferences: (any CalendarPreferenceManaging)?
    @State private var playbackSnapshot = PlaybackSnapshot.idle

    public init(authentication: (any AuthenticationManaging)? = nil, library: (any LibraryProviding)? = nil, playback: (any PlaybackControlling)? = nil, offline: (any OfflineManaging)? = nil, playlists: (any PlaylistManaging)? = nil, personalization: (any PersonalizationManaging)? = nil, context: (any ContextManaging)? = nil, calendarPreferences: (any CalendarPreferenceManaging)? = nil) {
        self.authentication = authentication
        self.library = library
        self.playback = playback
        self.offline = offline
        self.playlists = playlists
        self.personalization = personalization
        self.context = context
        self.calendarPreferences = calendarPreferences
    }

    public var body: some View {
        TabView(selection: $navigation.selectedTab) {
            tabNavigation(path: $navigation.homePath) { HomeScreen(library: library, playback: playback, offline: offline, personalization: personalization, calendarPreferences: calendarPreferences, playbackSnapshot: playbackSnapshot) }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)

            tabNavigation(path: $navigation.libraryPath) { LibraryScreen(library: library, playback: playback, offline: offline, playlists: playlists) }
                .tabItem { Label("Library", systemImage: "music.note.list") }
                .tag(AppTab.library)

            tabNavigation(path: $navigation.nowPath) { NowScreen(playback: playback, snapshot: playbackSnapshot) }
                .tabItem { Label("Now", systemImage: "play.circle") }
                .tag(AppTab.now)

            tabNavigation(path: $navigation.searchPath) { SearchScreen(query: $navigation.searchQuery, library: library, playback: playback, offline: offline, playlists: playlists) }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
        }
        .tint(selectedAccent.color)
        .preferredColorScheme(selectedTheme.colorScheme)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if playbackSnapshot.track != nil, let playback {
                MiniPlayer(snapshot: playbackSnapshot, playback: playback) { navigation.selectedTab = .now }
            }
        }
        .task {
            guard let playback else { return }
            for await value in playback.snapshots { playbackSnapshot = value }
        }
        .onOpenURL { _ = navigation.open($0) }
        .toolbar {
            Button("Appearance", systemImage: "paintpalette") { showsAppearance = true }
            if personalization != nil {
                Button("Learning & Privacy", systemImage: "brain.head.profile") { showsLearning = true }
            }
            if context != nil {
                Button("Activity & Context", systemImage: "figure.walk") { showsActivity = true }
            }
            if calendarPreferences != nil, playlists != nil {
                Button("Calendar & Smart Playlists", systemImage: "calendar") { showsCalendarPreferences = true }
            }
            if offline != nil {
                Button("Offline Storage", systemImage: "arrow.down.circle") { showsOffline = true }
            }
            if authentication != nil {
                Button("Account", systemImage: "person.crop.circle") { showsAccount = true }
            }
        }
        .sheet(isPresented: $showsAccount) {
            if let authentication {
                AccountSessionView(authentication: authentication)
            }
        }
        .sheet(isPresented: $showsOffline) {
            if let offline { OfflineSettingsView(offline: offline) }
        }
        .sheet(isPresented: $showsAppearance) {
            AppearanceSettingsView(themeRawValue: $themeRawValue, accentRawValue: $accentRawValue)
        }
        .sheet(isPresented: $showsLearning) {
            if let personalization { LearningPrivacyView(personalization: personalization) }
        }
        .sheet(isPresented: $showsActivity) {
            if let context { ActivityContextView(context: context) }
        }
        .sheet(isPresented: $showsCalendarPreferences) {
            if let calendarPreferences, let playlists { CalendarPreferenceView(preferences: calendarPreferences, playlists: playlists) }
        }
    }

    private var selectedTheme: UMusicThemePreference { UMusicThemePreference(rawValue: themeRawValue) ?? .system }
    private var selectedAccent: UMusicAccent { UMusicAccent(rawValue: accentRawValue) ?? .violet }

    private func tabNavigation<Content: View>(
        path: Binding<[AppRoute]>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack(path: path) {
            content()
                .navigationDestination(for: AppRoute.self) { route in
                    DeepLinkDestination(route: route, library: library, playback: playback, offline: offline, playlists: playlists)
                }
        }
    }
}

private struct ActivityContextView: View {
    let context: any ContextManaging
    @State private var snapshot = ContextSettingsSnapshot()
    @State private var detected: ActivityClassification?
    @State private var sessionActive = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Manual Activity") {
                    Picker("Activity", selection: Binding(get: { snapshot.selectedActivity }, set: { value in Task { await context.selectActivity(value); await reload() } })) {
                        ForEach(ListeningActivity.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Text("Manual selection always works and overrides automatic suggestions.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(sessionActive ? "Finish Activity Context" : "Start Activity Context", systemImage: sessionActive ? "stop.fill" : "play.fill") {
                        Task {
                            if sessionActive { await context.endListeningContext() } else { await context.beginListeningContext() }
                            sessionActive.toggle()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Section("Energy") {
                    Toggle("uMusic Low Energy Mode", isOn: signalBinding(get: { $0.lowEnergyMode }, set: { await context.setLowEnergyMode($0) }))
                    Text("This controls uMusic collection frequency. It cannot enable iOS Low Power Mode.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Optional Signals") {
#if os(iOS)
                    signalToggle("Five-second motion sample", signal: .motion, enabled: snapshot.motionEnabled)
                    signalToggle("Workout summaries", signal: .workout, enabled: snapshot.workoutEnabled)
#endif
                    signalToggle("One coarse outdoor context", signal: .coarseLocation, enabled: snapshot.coarseLocationEnabled)
                    signalToggle("Audio route category", signal: .audioRoute, enabled: snapshot.audioRouteEnabled)
                    signalToggle("Network class", signal: .network, enabled: snapshot.networkEnabled)
#if os(iOS)
                    Button("Sample Activity Now") { Task { await sampleNow() } }
                        .disabled(!snapshot.motionEnabled || snapshot.availability[.motion] != .available)
                    if let detected { Text("Suggestion: \(detected.activity.displayName) (\(detected.confidence, format: .percent.precision(.fractionLength(0))))") }
#endif
                }
                Section {
                    Text("Indoor activities never request location. Outdoor context requests one coarse classification and stops. No coordinate trail or accessory identifier is stored.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Activity & Context")
            .toolbar { Button("Done") { if sessionActive { Task { await context.endListeningContext() } }; dismiss() } }
            .task { await reload() }
            .alert("Context Unavailable", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
        }
    }

    private func signalBinding(get: @escaping (ContextSettingsSnapshot) -> Bool, set: @escaping (Bool) async -> Void) -> Binding<Bool> {
        Binding(get: { get(snapshot) }, set: { value in Task { await set(value); await reload() } })
    }
    private func signalToggle(_ title: LocalizedStringKey, signal: ContextSignal, enabled: Bool) -> some View {
        let availability = snapshot.availability[signal] ?? .unavailable
        return Toggle(title, isOn: Binding(get: { enabled }, set: { value in Task { await context.setSignal(signal, enabled: value); await reload() } }))
            .disabled(availability != .available)
    }
    private func reload() async { snapshot = await context.settings() }
    private func sampleNow() async { do { detected = try await context.sampleActivityNow() } catch { errorMessage = "The short motion sample could not complete." } }
}

private struct LearningPrivacyView: View {
    let personalization: any PersonalizationManaging
    @State private var snapshot = LearningSnapshot(retention: .ninetyDays, eventCount: 0, observationCount: 0, aggregateCount: 0, lastReducedSequence: 0)
    @State private var exportURL: URL?
    @State private var confirmsDelete = false
    @State private var confirmsReset = false
    @State private var fullPreview: ResearchExportPreview?
    @State private var confirmsFullExport = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Local Learning") {
                    LabeledContent("Raw events", value: "\(snapshot.eventCount)")
                    LabeledContent("Listening observations", value: "\(snapshot.observationCount)")
                    LabeledContent("Compact track aggregates", value: "\(snapshot.aggregateCount)")
                    Text("Learning data stays on this device unless you explicitly export it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Raw History Retention") {
                    Picker("Keep raw history", selection: Binding(get: { snapshot.retention }, set: { value in Task { await setRetention(value) } })) {
                        Text("7 days").tag(RawHistoryRetention.sevenDays)
                        Text("30 days").tag(RawHistoryRetention.thirtyDays)
                        Text("90 days").tag(RawHistoryRetention.ninetyDays)
                        Text("1 year").tag(RawHistoryRetention.oneYear)
                        Text("Indefinitely").tag(RawHistoryRetention.indefinite)
                    }
                    Text("Expired timelines are removed after compact, non-reconstructable affinity totals are updated.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Export") {
                    Button("Prepare Sanitized Export", systemImage: "square.and.arrow.up") { Task { await prepareExport() } }
                    Button("Preview Full Research Export", systemImage: "doc.badge.gearshape") { Task { await previewFullExport() } }
                    if let exportURL { ShareLink(item: exportURL) { Label("Share Export", systemImage: "paperplane") } }
                    Text("Sanitized packages exclude credentials, server details, usernames, file paths, coordinates, raw HealthKit values, and accessory identifiers. Full packages remain local until you explicitly share them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Delete") {
                    Button("Delete Raw History", role: .destructive) { confirmsDelete = true }
                    Button("Reset Learning", role: .destructive) { confirmsReset = true }
                    Text("Reset Learning removes raw history and learned aggregates. Your catalog, downloads, and manual playlists remain.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Learning & Privacy")
            .toolbar { Button("Done") { dismiss() } }
            .task { await reload() }
            .confirmationDialog("Delete listening history?", isPresented: $confirmsDelete) {
                Button("Delete Raw History", role: .destructive) { Task { await deleteHistory() } }
            } message: { Text("Compact learned aggregates will remain.") }
            .confirmationDialog("Reset all learning?", isPresented: $confirmsReset) {
                Button("Reset Learning", role: .destructive) { Task { await resetLearning() } }
            } message: { Text("This removes raw history and learned aggregates but preserves music and playlists.") }
            .confirmationDialog("Create Full Research Export?", isPresented: $confirmsFullExport) {
                Button("Create Full Export") { Task { await prepareFullExport() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Includes \(fullPreview?.eventCount ?? 0) events, \(fullPreview?.observationCount ?? 0) observations, track titles/artists, the complete listening timeline, and coarse activity/context. It remains local until shared.")
            }
            .alert("Learning Data Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
        }
    }

    private func reload() async { snapshot = await personalization.learningSnapshot() }
    private func setRetention(_ value: RawHistoryRetention) async { do { try await personalization.setRawHistoryRetention(value); await reload() } catch { errorMessage = "The retention setting could not be saved." } }
    private func deleteHistory() async { do { try await personalization.deleteHistory(); await reload() } catch { errorMessage = "Listening history could not be deleted." } }
    private func resetLearning() async { do { try await personalization.resetLearning(); await reload() } catch { errorMessage = "Learning data could not be reset." } }
    private func prepareExport() async { do { exportURL = try await personalization.exportResearch(.sanitized, confirmationID: nil) } catch { errorMessage = "The sanitized export could not be prepared." } }
    private func previewFullExport() async { fullPreview = await personalization.previewFullResearchExport(); confirmsFullExport = true }
    private func prepareFullExport() async { do { exportURL = try await personalization.exportResearch(.full, confirmationID: fullPreview?.confirmationID); fullPreview = nil } catch { errorMessage = "The full export preview expired or the package could not be prepared." } }
}

private struct AppearanceSettingsView: View {
    @Binding var themeRawValue: String
    @Binding var accentRawValue: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Color Scheme") {
                    Picker("Theme", selection: $themeRawValue) {
                        ForEach(UMusicThemePreference.allCases) { preference in
                            Text(preference.displayName).tag(preference.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Accent") {
                    Picker("Accent Color", selection: $accentRawValue) {
                        ForEach(UMusicAccent.allCases) { accent in
                            Label(accent.displayName, systemImage: "circle.fill")
                                .foregroundStyle(accent.color)
                                .tag(accent.rawValue)
                        }
                    }
                }
                Section {
                    Text("Text follows Dynamic Type. Motion effects follow Reduce Motion in System Settings.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Appearance")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

private struct OfflineSettingsView: View {
    let offline: any OfflineManaging
    @State private var snapshot = OfflineStorageSnapshot(usedBytes: 0, quotaBytes: 500 * 1_024 * 1_024)
    @State private var customMegabytes = ""
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Storage") {
                    ProgressView(value: Double(snapshot.usedBytes), total: Double(max(snapshot.quotaBytes, 1)))
                    Text("\(ByteCountFormatter.string(fromByteCount: snapshot.usedBytes, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: snapshot.quotaBytes, countStyle: .file))")
                    Picker("Quota", selection: Binding(get: { snapshot.quotaBytes }, set: { value in Task { await applyQuota(value) } })) {
                        Text("100 MB").tag(Int64(100 * 1_024 * 1_024))
                        Text("500 MB").tag(Int64(500 * 1_024 * 1_024))
                        Text("1 GB").tag(Int64(1_024 * 1_024 * 1_024))
                    }
                    HStack {
                        TextField("Custom MB", text: $customMegabytes)
                        Button("Apply") { Task { if let mb = Int64(customMegabytes), mb >= 0 { await applyQuota(mb * 1_024 * 1_024) } } }
                    }
                }
                Section("Network") {
                    Toggle("Allow cellular downloads", isOn: Binding(get: { snapshot.allowsCellular }, set: { value in Task { await offline.setAllowsCellular(value); await reload() } }))
                    Text(snapshot.allowsCellular ? "Downloads may use cellular data." : "Downloads wait for Wi-Fi or another unmetered connection.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Downloaded") {
                    if snapshot.entries.isEmpty { Text("No offline music") }
                    ForEach(snapshot.entries) { entry in
                        HStack {
                            VStack(alignment: .leading) { Text(entry.title); Text("\(entry.artist) · \(entry.retention.rawValue.capitalized)").font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Text(ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)).font(.caption)
                            Button("Remove", systemImage: "trash", role: .destructive) { Task { do { try await offline.removeDownload(trackID: entry.trackID); await reload() } catch { errorMessage = "This download cannot be removed while it is playing." } } }.labelStyle(.iconOnly)
                        }
                    }
                }
            }
            .navigationTitle("Offline Storage")
            .toolbar { Button("Done") { dismiss() } }
            .task { await reload() }
            .alert("Storage Change Failed", isPresented: .constant(errorMessage != nil)) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
        }
    }

    private func reload() async { snapshot = await offline.storageSnapshot() }
    private func applyQuota(_ bytes: Int64) async {
        do { try await offline.setQuota(bytes: bytes); await reload() }
        catch { errorMessage = "Pinned or currently playing music does not fit in that quota." }
    }
}

private struct AccountSessionView: View {
    let authentication: any AuthenticationManaging
    @State private var disposition: LogoutLocalDataDisposition = .keep
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("When logging out", selection: $disposition) {
                    Text("Keep local music and learning").tag(LogoutLocalDataDisposition.keep)
                    Text("Remove offline music").tag(LogoutLocalDataDisposition.removeOfflineMedia)
                    Text("Remove learning history").tag(LogoutLocalDataDisposition.removeLearningHistory)
                    Text("Remove all device data").tag(LogoutLocalDataDisposition.removeAllDeviceData)
                }
                Button("Log Out", role: .destructive) {
                    Task {
                        await authentication.logout(localData: disposition)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Account")
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }
}

private struct CalendarPreferenceView: View {
    let preferences: any CalendarPreferenceManaging
    let playlists: any PlaylistManaging
    @State private var snapshot = CalendarPreferenceSnapshot()
    @State private var summaries: [PlaylistSummary] = []
    @State private var selectedPlaylistID: UUID?
    @State private var start = Date()
    @State private var end = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var calendarVersion = "manual-1"
    @State private var grows = false
    @State private var requiresApproval = true
    @State private var weeklyLimit = 10
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Ramadan preference") {
                    Picker("Behavior", selection: Binding(get: { snapshot.preference }, set: { value in Task { await savePreference(value) } })) {
                        Text("Off").tag(RamadanPreference.off)
                        Text("Suggest").tag(RamadanPreference.suggest)
                        Text("Prefer").tag(RamadanPreference.prefer)
                    }
                    Picker("Playlist", selection: $selectedPlaylistID) {
                        Text("None").tag(UUID?.none)
                        ForEach(summaries) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    Button("Save selected playlist") { Task { await savePreference(snapshot.preference) } }
                    Picker("Instant override", selection: Binding(get: { snapshot.instantOverride.map { $0 ? 1 : 0 } ?? -1 }, set: { value in Task { try? await preferences.setInstantOverride(value < 0 ? nil : value == 1); await reload() } })) {
                        Text("Use calendar").tag(-1); Text("Inactive now").tag(0); Text("Active now").tag(1)
                    }
                    Text("uMusic never infers religion. Calendar status has no effect while Off and never selects content without your chosen playlist.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Local calendar window") {
                    DatePicker("Starts", selection: $start)
                    DatePicker("Ends", selection: $end)
                    TextField("Calendar version", text: $calendarVersion)
                    Button("Save manual correction") { Task { await saveWindow() } }.disabled(end <= start)
                    if let window = snapshot.window { Text("\(window.version) · \(window.timeZoneIdentifier)").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Smart playlist") {
                    Toggle("Automatically grow", isOn: $grows)
                    Toggle("Require approval", isOn: $requiresApproval)
                    Stepper("Weekly cap: \(weeklyLimit)", value: $weeklyLimit, in: 0...100)
                    Button("Save Quran and translation rule") { Task { await saveRule() } }.disabled(selectedPlaylistID == nil)
                    Text("Auto-grow defaults off. Only explicit server classifications at 80% confidence or higher match; language, title, location, and listening behavior are ignored.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !snapshot.pending.isEmpty {
                    Section("Awaiting approval") {
                        ForEach(snapshot.pending) { entry in
                            HStack { Text("\(entry.trackIDs.count) proposed songs"); Spacer(); Button("Approve") { Task { try? await preferences.approve(auditID: entry.id, at: Date()); await reload() } } }
                        }
                    }
                }
                if !snapshot.audit.filter({ $0.action == .added }).isEmpty {
                    Section("Recent automatic changes") {
                        ForEach(snapshot.audit.filter { $0.action == .added }.suffix(10)) { entry in
                            HStack { Text("Added \(entry.trackIDs.count) songs"); Spacer(); Button("Undo") { Task { try? await preferences.undo(auditID: entry.id, at: Date()); await reload() } } }
                        }
                    }
                }
            }
            .navigationTitle("Calendar & Playlists")
            .toolbar { Button("Done") { dismiss() } }
            .task { await reload() }
            .alert("Unable to save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func reload() async {
        snapshot = await preferences.snapshot(); summaries = (try? await playlists.playlists()) ?? []
        selectedPlaylistID = snapshot.selectedPlaylistID
        if let window = snapshot.window { start = window.start; end = window.end; calendarVersion = window.version }
        if let id = selectedPlaylistID, let rule = snapshot.rules.first(where: { $0.playlistID == id }) { grows = rule.automaticallyGrows; requiresApproval = rule.requiresApproval; weeklyLimit = rule.weeklyAdditionLimit }
    }
    private func savePreference(_ value: RamadanPreference) async {
        do { try await preferences.setPreference(value, selectedPlaylistID: selectedPlaylistID); await reload() } catch { errorMessage = "Choose an existing playlist before saving." }
    }
    private func saveWindow() async {
        do { try await preferences.setCalendarWindow(CalendarWindow(start: start, end: end, timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier, version: calendarVersion, manuallyCorrected: true)); await reload() } catch { errorMessage = "The calendar window could not be saved." }
    }
    private func saveRule() async {
        guard let selectedPlaylistID else { return }
        do {
            try await preferences.setRule(.init(playlistID: selectedPlaylistID, automaticallyGrows: grows, categories: [.quran, .quranTranslation], minimumConfidence: 0.8, weeklyAdditionLimit: weeklyLimit, requiresApproval: requiresApproval))
            try await preferences.evaluateSmartPlaylists(at: Date(), calendar: .autoupdatingCurrent)
            await reload()
        } catch { errorMessage = "The playlist changed or no longer exists. Reload and choose another." }
    }
}

#Preview {
    AppShellView()
}
