import Foundation

#if os(iOS)
import HealthKit
import UIKit

@MainActor
final class HealthWorkoutService: NSObject, ObservableObject {
    static let shared = HealthWorkoutService()

    @Published private(set) var authorized = false
    @Published private(set) var active = false
    @Published private(set) var heartRate: Double?
    @Published private(set) var activeCalories: Double = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var steps: Double = 0
    @Published private(set) var activityName = "No activity"
    @Published private(set) var heartRateSource = "No sensor sample"
    @Published private(set) var heartRateStatus = "Start a Health workout to collect heart rate"
    @Published private(set) var lastHeartRateAt: Date?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var workoutStart: Date?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        if UserDefaults.standard.bool(forKey: "uMusicWorkoutWasActive") {
            Task { await endRecoveredWorkoutIfNeeded() }
        }
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            heartRateStatus = "Apple Health is unavailable on this device"
            return
        }
        let readable = Set([
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling),
            HKQuantityType(.stepCount),
        ])
        do {
            try await store.requestAuthorization(
                toShare: [HKObjectType.workoutType()], read: readable
            )
            authorized = true
            heartRateStatus = "Health access requested; start a workout"
        } catch {
            authorized = false
            heartRateStatus = "Health authorization failed: \(error.localizedDescription)"
        }
    }

    func start(kind: String, name: String? = nil) async {
        guard authorized else {
            heartRateStatus = "Allow Heart Rate and Workouts access in Settings → Health"
            return
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType(kind)
        configuration.locationType = ["cycling", "running", "walking"].contains(kind)
            ? .outdoor : .indoor
        do {
            let session = try HKWorkoutSession(
                healthStore: store, configuration: configuration
            )
            let builder = session.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(
                healthStore: store, workoutConfiguration: configuration
            )
            let heartType = HKQuantityType(.heartRate)
            dataSource.enableCollection(for: heartType, predicate: nil)
            builder.dataSource = dataSource
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            heartRate = nil
            heartRateSource = "Waiting for AirPods, Watch, or paired sensor"
            heartRateStatus = dataSource.typesToCollect.contains(heartType)
                ? "Heart-rate collection active; waiting for first sample"
                : "Heart rate is not available from a paired sensor"
            lastHeartRateAt = nil
            activeCalories = 0
            distanceMeters = 0
            steps = 0
            activityName = name ?? kind.capitalized
            let start = Date()
            workoutStart = start
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            active = true
            UserDefaults.standard.set(true, forKey: "uMusicWorkoutWasActive")
        } catch {
            active = false
            heartRateStatus = "Workout could not start: \(error.localizedDescription)"
        }
    }

    func stop() async {
        guard let builder else { return }
        let end = Date()
        session?.end()
        try? await builder.endCollection(at: end)
        _ = try? await builder.finishWorkout()
        self.builder = nil
        session = nil
        active = false
        workoutStart = nil
        UserDefaults.standard.set(false, forKey: "uMusicWorkoutWasActive")
    }

    @objc private func applicationWillTerminate() {
        session?.end()
        active = false
        UserDefaults.standard.set(false, forKey: "uMusicWorkoutWasActive")
    }

    private func endRecoveredWorkoutIfNeeded() async {
        do {
            if let recovered = try await store.recoverActiveWorkoutSession() {
                recovered.end()
                heartRateStatus = "A workout left active by the previous app session was stopped"
            }
        } catch {
            heartRateStatus = "Could not recover the previous workout: \(error.localizedDescription)"
        }
        UserDefaults.standard.set(false, forKey: "uMusicWorkoutWasActive")
    }

    private func handleSessionEnded(message: String) {
        active = false
        session = nil
        workoutStart = nil
        UserDefaults.standard.set(false, forKey: "uMusicWorkoutWasActive")
        heartRateStatus = message
        guard let builder else { return }
        self.builder = nil
        Task {
            try? await builder.endCollection(at: Date())
            _ = try? await builder.finishWorkout()
        }
    }

    private func updateStatistics(for types: Set<HKSampleType>) {
        guard let builder else { return }
        for type in types {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = builder.statistics(for: quantityType) else { continue }
            switch quantityType.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                heartRate = statistics.mostRecentQuantity()?.doubleValue(
                    for: HKUnit.count().unitDivided(by: .minute())
                )
                if heartRate != nil {
                    lastHeartRateAt = Date()
                    heartRateStatus = "Receiving live heart-rate samples"
                    updateHeartRateSource()
                }
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                activeCalories = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
                 HKQuantityTypeIdentifier.distanceCycling.rawValue:
                distanceMeters = statistics.sumQuantity()?.doubleValue(for: .meter()) ?? 0
            case HKQuantityTypeIdentifier.stepCount.rawValue:
                steps = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
            default: break
            }
        }
    }

    private func updateHeartRateSource() {
        guard let workoutStart else { return }
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: workoutStart, end: nil, options: .strictStartDate
        )
        let query = HKSampleQuery(
            sampleType: type, predicate: predicate, limit: 1,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        ) { [weak self] _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else { return }
            let source = sample.device?.name ?? sample.sourceRevision.source.name
            Task { @MainActor in self?.heartRateSource = source }
        }
        store.execute(query)
    }

    private static func activityType(_ kind: String) -> HKWorkoutActivityType {
        switch kind {
        case "cycling": .cycling
        case "running": .running
        case "walking": .walking
        case "gym": .traditionalStrengthTraining
        case "relax": .mindAndBody
        default: .other
        }
    }
}

extension HealthWorkoutService: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState, date: Date
    ) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor in self.handleSessionEnded(message: "Workout ended") }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession, didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.session?.end()
            self.handleSessionEnded(message: "Workout ended: \(error.localizedDescription)")
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in self.updateStatistics(for: collectedTypes) }
    }
}
#else
@MainActor
final class HealthWorkoutService: ObservableObject {
    static let shared = HealthWorkoutService()
    @Published private(set) var authorized = false
    @Published private(set) var active = false
    @Published private(set) var heartRate: Double?
    @Published private(set) var activeCalories: Double = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var steps: Double = 0
    @Published private(set) var activityName = "No activity"
    @Published private(set) var heartRateSource = "Unavailable on macOS"
    @Published private(set) var heartRateStatus = "Live sensor data requires iPhone"
    @Published private(set) var lastHeartRateAt: Date?
    func requestAuthorization() async {}
    func start(kind: String, name: String? = nil) async {
        activityName = name ?? kind.capitalized
        active = true
        heartRateStatus = "Manual uMusic session active; live Health sensors require iPhone"
    }
    func stop() async {
        active = false
        activityName = "No activity"
        heartRateStatus = "Live sensor data requires iPhone"
    }
}
#endif
