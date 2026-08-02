import Foundation

#if os(iOS)
import CoreMotion

@MainActor
final class ActivityDetectionService: ObservableObject {
    static let shared = ActivityDetectionService()
    @Published private(set) var detectedKind: String?
    @Published private(set) var confidence = "Unknown"
    @Published private(set) var active = false
    private let manager = CMMotionActivityManager()
    private var samplingTask: Task<Void, Never>?

    func start() {
        guard CMMotionActivityManager.isActivityAvailable(), !active else { return }
        detectedKind = nil
        confidence = "Waiting"
        active = true
        samplingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppEnergyPolicy.lowEnergyEnabled ? 5 : 8))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            Task { @MainActor in
                self.confidence = switch activity.confidence {
                case .high: "High"
                case .medium: "Medium"
                default: "Low"
                }
                if activity.cycling { self.detectedKind = "cycling" }
                else if activity.running { self.detectedKind = "running" }
                else if activity.walking { self.detectedKind = "walking" }
                else if activity.stationary { self.detectedKind = "stationary" }
                else if activity.automotive { self.detectedKind = "automotive" }
                else { self.detectedKind = nil }
            }
        }
    }

    func stop() {
        samplingTask?.cancel()
        samplingTask = nil
        manager.stopActivityUpdates()
        active = false
    }
}
#else
@MainActor
final class ActivityDetectionService: ObservableObject {
    static let shared = ActivityDetectionService()
    @Published private(set) var detectedKind: String?
    @Published private(set) var confidence = "Unavailable"
    @Published private(set) var active = false
    func start() {}
    func stop() {}
}
#endif
