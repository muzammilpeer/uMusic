import Foundation
import UMusicDomain
import UMusicSupport

public enum ContextModule {
    public static let defaultsToLowEnergy = true
    public static let lowEnergyMotionSampleSeconds: Double = 5
}

private struct ContextSettingsDocument: Codable {
    var schemaVersion = 1
    var lowEnergyMode = true
    var selectedActivity = ListeningActivity.unknown
    var enabledSignals: Set<ContextSignal> = []
}

public actor ContextCoordinator: ContextManaging {
    public nonisolated let snapshots: AsyncStream<ContextSettingsSnapshot>
    private let continuation: AsyncStream<ContextSettingsSnapshot>.Continuation
    private let settingsURL: URL
    private let motion: any MotionActivitySampling
    private let workout: any WorkoutContextCollecting
    private let place: any CoarsePlaceClassifying
    private let route: any AudioRouteProviding
    private let network: any NetworkClassProviding
    private let learning: (any ContextLearningRecording)?
    private var document: ContextSettingsDocument
    private var active = false

    public init(settingsURL: URL, motion: any MotionActivitySampling = UnavailableMotionSampler(), workout: any WorkoutContextCollecting = UnavailableWorkoutCollector(), place: any CoarsePlaceClassifying = UnavailablePlaceClassifier(), route: any AudioRouteProviding = SystemAudioRouteProvider(), network: any NetworkClassProviding = SystemNetworkClassProvider(), learning: (any ContextLearningRecording)? = nil) {
        self.settingsURL = settingsURL; self.motion = motion; self.workout = workout
        self.place = place; self.route = route; self.network = network; self.learning = learning
        document = (try? Data(contentsOf: settingsURL)).flatMap { try? JSONDecoder().decode(ContextSettingsDocument.self, from: $0) } ?? ContextSettingsDocument()
        let stream = AsyncStream<ContextSettingsSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(2))
        snapshots = stream.stream; continuation = stream.continuation
        continuation.yield(Self.makeSnapshot(document: document, motion: motion.availability, workout: workout.availability, place: place.availability))
    }

    deinit { continuation.finish() }

    public func settings() async -> ContextSettingsSnapshot { makeSnapshot() }

    public func selectActivity(_ activity: ListeningActivity) async {
        document.selectedActivity = activity; persistAndEmit()
        if active { await publishContext(activitySource: .manual, confidence: 1) }
    }

    public func setLowEnergyMode(_ enabled: Bool) async { document.lowEnergyMode = enabled; persistAndEmit() }

    public func setSignal(_ signal: ContextSignal, enabled: Bool) async {
        let availability = availability(for: signal)
        if enabled && availability == .available {
            document.enabledSignals.insert(signal)
            await learning?.recordContextConsent(signal: signal, status: .granted)
        } else {
            document.enabledSignals.remove(signal)
            await learning?.recordContextConsent(signal: signal, status: enabled ? .denied : .revoked)
            await stop(signal)
        }
        persistAndEmit()
    }

    public func sampleActivityNow() async throws -> ActivityClassification? {
        guard document.enabledSignals.contains(.motion), motion.availability == .available else { return nil }
        let seconds = document.lowEnergyMode ? ContextModule.lowEnergyMotionSampleSeconds : 10
        let result = try await motion.sample(for: seconds)
        await motion.stop()
        return result
    }

    public func beginListeningContext() async {
        active = true
        if document.enabledSignals.contains(.workout), workout.availability == .available { try? await workout.start(activity: document.selectedActivity) }
        await publishContext(activitySource: .manual, confidence: 1)
    }

    public func endListeningContext() async {
        active = false
        await motion.stop(); await workout.stop(); await place.stop()
    }

    private func publishContext(activitySource: ActivitySource, confidence: Double) async {
        let activity = document.selectedActivity
        let placeClass: CoarsePlaceClass
        if Self.isIndoor(activity) { placeClass = .indoors }
        else if Self.isOutdoor(activity), document.enabledSignals.contains(.coarseLocation), place.availability == .available {
            placeClass = (try? await place.classifyOnce()) ?? .unknown
            await place.stop()
        } else { placeClass = .unknown }
        let routeCategory = document.enabledSignals.contains(.audioRoute) ? await route.currentCategory() : .unknown
        let networkClass = document.enabledSignals.contains(.network) ? await network.currentClass() : .unknown
        await learning?.updateContext(ContextSnapshot(date: Date(), calendar: .autoupdatingCurrent, activity: activity, activitySource: activitySource, activityConfidence: confidence, placeClass: placeClass, routeCategory: routeCategory, networkClass: networkClass, lowEnergyMode: document.lowEnergyMode))
    }

    private func availability(for signal: ContextSignal) -> SignalAvailability {
        switch signal {
        case .motion: motion.availability
        case .workout: workout.availability
        case .coarseLocation: place.availability
        case .audioRoute, .network: .available
        }
    }

    private func stop(_ signal: ContextSignal) async {
        switch signal { case .motion: await motion.stop(); case .workout: await workout.stop(); case .coarseLocation: await place.stop(); case .audioRoute, .network: break }
    }

    private func makeSnapshot() -> ContextSettingsSnapshot { Self.makeSnapshot(document: document, motion: motion.availability, workout: workout.availability, place: place.availability) }
    private static func makeSnapshot(document: ContextSettingsDocument, motion: SignalAvailability, workout: SignalAvailability, place: SignalAvailability) -> ContextSettingsSnapshot {
        ContextSettingsSnapshot(lowEnergyMode: document.lowEnergyMode, selectedActivity: document.selectedActivity, motionEnabled: document.enabledSignals.contains(.motion), workoutEnabled: document.enabledSignals.contains(.workout), coarseLocationEnabled: document.enabledSignals.contains(.coarseLocation), audioRouteEnabled: document.enabledSignals.contains(.audioRoute), networkEnabled: document.enabledSignals.contains(.network), availability: [.motion: motion, .workout: workout, .coarseLocation: place, .audioRoute: .available, .network: .available])
    }

    private func persistAndEmit() {
        try? FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(document) { try? data.write(to: settingsURL, options: [.atomic, .completeFileProtection]) }
        continuation.yield(makeSnapshot())
    }

    public static func isIndoor(_ activity: ListeningActivity) -> Bool { [.gym, .focus, .relaxation].contains(activity) }
    public static func isOutdoor(_ activity: ListeningActivity) -> Bool { [.walking, .running, .cycling].contains(activity) }
}

public struct UnavailableMotionSampler: MotionActivitySampling {
    public let availability: SignalAvailability
    public init(availability: SignalAvailability = .unavailable) { self.availability = availability }
    public func sample(for seconds: Double) async throws -> ActivityClassification? { nil }
    public func stop() async {}
}
public struct UnavailableWorkoutCollector: WorkoutContextCollecting {
    public let availability: SignalAvailability
    public init(availability: SignalAvailability = .unavailable) { self.availability = availability }
    public func start(activity: ListeningActivity) async throws {}
    public func stop() async {}
}
public struct UnavailablePlaceClassifier: CoarsePlaceClassifying {
    public let availability: SignalAvailability
    public init(availability: SignalAvailability = .unavailable) { self.availability = availability }
    public func classifyOnce() async throws -> CoarsePlaceClass { .unknown }
    public func stop() async {}
}
public struct UnknownAudioRouteProvider: AudioRouteProviding { public init() {}; public func currentCategory() async -> AudioRouteCategory { .unknown } }
public struct UnknownNetworkClassProvider: NetworkClassProviding { public init() {}; public func currentClass() async -> NetworkClass { .unknown } }
