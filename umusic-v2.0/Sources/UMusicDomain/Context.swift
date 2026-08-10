import Foundation

public enum ActivitySource: String, Codable, Sendable { case manual, motionSample, workout, unknown }
public enum CoarsePlaceClass: String, Codable, CaseIterable, Sendable { case unknown, indoors, outdoors }
public enum AudioRouteCategory: String, Codable, CaseIterable, Sendable { case unknown, builtIn, wired, bluetooth, airPlay, car }
public enum NetworkClass: String, Codable, CaseIterable, Sendable { case unknown, offline, metered, unmetered }
public enum ContextSignal: String, Codable, CaseIterable, Sendable, Identifiable { case motion, workout, coarseLocation, audioRoute, network
    public var id: String { rawValue }
}
public enum SignalAvailability: String, Codable, Sendable { case available, unavailable, denied, restricted }

public struct ContextSettingsSnapshot: Codable, Equatable, Sendable {
    public let lowEnergyMode: Bool
    public let selectedActivity: ListeningActivity
    public let motionEnabled: Bool
    public let workoutEnabled: Bool
    public let coarseLocationEnabled: Bool
    public let audioRouteEnabled: Bool
    public let networkEnabled: Bool
    public let availability: [ContextSignal: SignalAvailability]

    public init(lowEnergyMode: Bool = true, selectedActivity: ListeningActivity = .unknown, motionEnabled: Bool = false, workoutEnabled: Bool = false, coarseLocationEnabled: Bool = false, audioRouteEnabled: Bool = false, networkEnabled: Bool = false, availability: [ContextSignal: SignalAvailability] = [:]) {
        self.lowEnergyMode = lowEnergyMode; self.selectedActivity = selectedActivity
        self.motionEnabled = motionEnabled; self.workoutEnabled = workoutEnabled
        self.coarseLocationEnabled = coarseLocationEnabled; self.audioRouteEnabled = audioRouteEnabled
        self.networkEnabled = networkEnabled; self.availability = availability
    }
}

public struct ActivityClassification: Codable, Equatable, Sendable {
    public let activity: ListeningActivity
    public let confidence: Double
    public init(activity: ListeningActivity, confidence: Double) { self.activity = activity; self.confidence = min(max(confidence, 0), 1) }
}

public protocol MotionActivitySampling: Sendable {
    var availability: SignalAvailability { get }
    func sample(for seconds: Double) async throws -> ActivityClassification?
    func stop() async
}
public protocol WorkoutContextCollecting: Sendable {
    var availability: SignalAvailability { get }
    func start(activity: ListeningActivity) async throws
    func stop() async
}
public protocol CoarsePlaceClassifying: Sendable {
    var availability: SignalAvailability { get }
    func classifyOnce() async throws -> CoarsePlaceClass
    func stop() async
}
public protocol AudioRouteProviding: Sendable { func currentCategory() async -> AudioRouteCategory }
public protocol NetworkClassProviding: Sendable { func currentClass() async -> NetworkClass }
public protocol ContextLearningRecording: Sendable {
    func updateContext(_ snapshot: ContextSnapshot) async
    func recordContextConsent(signal: ContextSignal, status: ConsentStatus) async
}

public protocol ContextManaging: Sendable {
    var snapshots: AsyncStream<ContextSettingsSnapshot> { get }
    func settings() async -> ContextSettingsSnapshot
    func selectActivity(_ activity: ListeningActivity) async
    func setLowEnergyMode(_ enabled: Bool) async
    func setSignal(_ signal: ContextSignal, enabled: Bool) async
    func sampleActivityNow() async throws -> ActivityClassification?
    func beginListeningContext() async
    func endListeningContext() async
}
