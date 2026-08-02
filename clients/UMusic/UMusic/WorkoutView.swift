import CoreLocation
import Combine
import SwiftUI

@MainActor
final class WorkoutViewModel: ObservableObject {
    @Published var activities: [WorkoutActivity] = []
    @Published var places: [Place] = []
    @Published var selectedActivityID: UUID?
    @Published var selectedPlaceID: UUID?
    @Published var durationMinutes = 60
    @Published var targetEnergy = 0.75
    @Published var customActivityName = ""
    @Published var useHealthKit = true
    @Published var rawRouteOptIn = false {
        didSet { location.rawRouteOptIn = rawRouteOptIn }
    }
    @Published var autoDetectActivity = true
    @Published private(set) var running = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var phase = WorkoutPhase.steady
    @Published var message = "Choose an activity"

    let location = LocationContextService.shared
    let health = HealthWorkoutService.shared
    let detector = ActivityDetectionService.shared
    private let api: any WorkoutMusicAPI
    private var ticker: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []

    init(api: any WorkoutMusicAPI = APIClient()) {
        self.api = api
        detector.$detectedKind
            .compactMap { $0 }
            .sink { [weak self] kind in
                guard let self, self.autoDetectActivity, !self.running,
                      let match = self.activities.first(where: { $0.kind == kind }) else { return }
                self.selectedActivityID = match.id
                self.message = "Detected \(match.name) (\(self.detector.confidence) confidence)"
                if self.detector.confidence != "Low" { self.detector.stop() }
            }
            .store(in: &subscriptions)
    }

    var activity: WorkoutActivity? { activities.first { $0.id == selectedActivityID } }

    func load(server: URL, token: String) async {
        do {
            async let loadedActivities = api.workoutActivities(server: server, token: token)
            async let loadedPlaces = api.places(server: server, token: token)
            activities = try await loadedActivities
            places = try await loadedPlaces
            selectedActivityID = selectedActivityID ?? activities.first?.id
        } catch { message = error.localizedDescription }
    }

    func resolvePlace() {
        location.requestOneShot()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            if let place = self.location.nearestPlace(in: self.places) {
                self.selectedPlaceID = place.id
                self.message = "Using nearby place: \(place.name)"
            } else if self.location.authorization == .denied {
                self.message = "Location denied; manual activity and place remain available"
            } else {
                self.message = "No configured place matched; using manual context"
            }
        }
    }

    func addCustomActivity(server: URL, token: String) async {
        let name = customActivityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let activity = try await api.createCustomActivity(
                server: server, token: token, name: name
            )
            activities.append(activity)
            selectedActivityID = activity.id
            customActivityName = ""
        } catch { message = error.localizedDescription }
    }

    func start(server: URL, token: String, player: AudioPlayer) async {
        guard let activity else { return }
        if useHealthKit {
            await health.requestAuthorization()
            await health.start(kind: activity.kind, name: activity.name)
        }
        detector.stop()
        location.startTracking(kind: activity.kind)
        elapsed = 0
        phase = WorkoutPhaseEngine(
            phases: activity.phaseCurve, duration: Double(durationMinutes * 60)
        ).phase(at: 0)
        await publishContext(server: server, token: token, player: player)
        running = true
        message = "\(activity.name) session active"
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, self.running else { return }
                self.elapsed += 15
                let next = WorkoutPhaseEngine(
                    phases: activity.phaseCurve, duration: Double(self.durationMinutes * 60)
                ).phase(at: self.elapsed)
                if next != self.phase {
                    self.phase = next
                    await self.publishContext(server: server, token: token, player: player)
                }
                let heartDemand = self.health.heartRate.map {
                    min(1, max(0.35, ($0 - 60) / 120))
                } ?? self.targetEnergy
                let adaptiveEnergy = min(
                    1, (self.targetEnergy * 0.65 + heartDemand * 0.35)
                        * self.phase.energyMultiplier
                )
                player.rerankFutureTracks(targetEnergy: adaptiveEnergy, limit: 8)
            }
        }
    }

    func stop() async {
        ticker?.cancel()
        ticker = nil
        running = false
        await health.stop()
        location.stopTracking()
        message = "Session finished"
    }

    func setAutoDetection(_ enabled: Bool) {
        autoDetectActivity = enabled
        if !enabled { detector.stop() }
    }

    func detectActivityNow() {
        guard autoDetectActivity, !running else { return }
        detector.start()
    }

    func viewDidDisappear() {
        if !running { detector.stop() }
    }

    private func publishContext(server: URL, token: String, player: AudioPlayer) async {
        guard let activity else { return }
        let snapshot = try? await api.createContext(
            server: server, token: token, activityID: activity.id,
            placeID: selectedPlaceID, phase: phase, durationMinutes: durationMinutes,
            targetEnergy: targetEnergy
        )
        if let snapshot { player.configureContext(snapshotID: snapshot.id) }
        player.rerankFutureTracks(
            targetEnergy: min(1, targetEnergy * phase.energyMultiplier), limit: 8
        )
    }
}

struct WorkoutView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: AudioPlayer
    @StateObject private var model = WorkoutViewModel()
    @AppStorage("uMusicLowEnergyMode") private var lowEnergyMode = true

    var body: some View {
        Form {
            Section {
                if model.running {
                    Button(role: .destructive) {
                        Task { await model.stop() }
                    } label: {
                        Label("Finish Workout Session", systemImage: "stop.circle.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                } else {
                    Button {
                        guard let server = session.server, let token = session.token else { return }
                        Task { await model.start(server: server, token: token, player: player) }
                    } label: {
                        Label("Start Workout Session", systemImage: "figure.run.circle.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.activity == nil)
                }
                Text(model.message)
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            Section("Session") {
                Picker("Activity", selection: $model.selectedActivityID) {
                    ForEach(model.activities) { Text($0.name).tag(Optional($0.id)) }
                }
                #if os(iOS)
                Toggle("Enable activity detection", isOn: Binding(
                    get: { model.autoDetectActivity },
                    set: { model.setAutoDetection($0) }
                ))
                LabeledContent(
                    "Last detected",
                    value: model.detector.detectedKind?.capitalized ?? "Waiting for movement"
                )
                LabeledContent("Motion sensor", value: model.detector.active ? "Sampling" : "Off")
                LabeledContent("Last result confidence", value: model.detector.confidence)
                Button("Detect activity now", systemImage: "figure.run") {
                    model.detectActivityNow()
                }
                .disabled(!model.autoDetectActivity || model.running || model.detector.active)
                Text("Motion is sampled for up to 5 seconds in Low Energy Mode, only when requested.")
                    .font(.caption).foregroundStyle(.secondary)
                #else
                LabeledContent("Activity detection", value: "Manual on Mac")
                Text("Mac does not provide the iPhone motion-activity sensor. Choose the activity above.")
                    .font(.caption).foregroundStyle(.secondary)
                #endif
                HStack {
                    TextField("Custom activity", text: $model.customActivityName)
                    Button("Add") {
                        guard let server = session.server, let token = session.token else { return }
                        Task { await model.addCustomActivity(server: server, token: token) }
                    }
                }
                Picker("Place", selection: $model.selectedPlaceID) {
                    Text("Manual / none").tag(UUID?.none)
                    ForEach(model.places) { Text($0.name).tag(Optional($0.id)) }
                }
                Button("Resolve nearby place", systemImage: "location") { model.resolvePlace() }
                Stepper(
                    "Duration: \(model.durationMinutes) minutes", value: $model.durationMinutes,
                    in: 15...240, step: 15
                )
                #if os(iOS)
                Toggle("Create Health workout", isOn: $model.useHealthKit)
                #else
                LabeledContent("Session tracking", value: "uMusic activity session")
                #endif
                Toggle("Store raw route", isOn: $model.rawRouteOptIn)
                Text(model.rawRouteOptIn
                     ? "Route recording uses coarse, distance-filtered GPS and stays on this device."
                     : "Location uses one coarse fix at workout start; continuous GPS stays off.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Workout controls") {
                Text(model.phase.title).font(.largeTitle.bold())
                Text(Duration.seconds(model.elapsed).formatted(.time(pattern: .hourMinuteSecond)))
                    .font(.title.monospacedDigit())
                HStack(spacing: 28) {
                    Button { player.previous() } label: { Image(systemName: "backward.fill") }
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 56))
                    }
                    Button { player.next() } label: { Image(systemName: "forward.fill") }
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            Section("Privacy and battery") {
                Toggle("uMusic Low Energy Mode", isOn: $lowEnergyMode)
                Text("Enabled by default. Uses shorter motion sampling, coarser GPS, and less frequent network telemetry.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Location", value: model.location.authorizationLabel)
                #if os(iOS)
                LabeledContent("Health workout", value: model.health.active ? "Active" : "Off")
                LabeledContent("Heart-rate sensor", value: model.health.heartRateSource)
                Text(model.health.heartRateStatus)
                    .font(.caption).foregroundStyle(
                        model.health.heartRate == nil && model.health.active ? .orange : .secondary
                    )
                Button("Request Health Access", systemImage: "heart.text.clipboard") {
                    Task { await model.health.requestAuthorization() }
                }
                #else
                LabeledContent("Apple Health", value: "Available on iPhone")
                #endif
                LabeledContent("System Low Power Mode", value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off")
                Button("Erase recorded route", role: .destructive) { model.location.eraseRecordedRoute() }
            }
        }
        .navigationTitle("Workout")
        .task {
            guard let server = session.server, let token = session.token else { return }
            await model.load(server: server, token: token)
        }
        .onDisappear { model.viewDidDisappear() }
    }
}
