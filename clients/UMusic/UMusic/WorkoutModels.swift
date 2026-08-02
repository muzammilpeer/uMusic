import Foundation

enum WorkoutPhase: String, Codable, CaseIterable, Sendable {
    case warmup, sustain, recovery, cooldown, rest, steady

    var title: String { rawValue.capitalized }
    var energyMultiplier: Double {
        switch self {
        case .warmup: 0.72
        case .sustain: 1.0
        case .recovery: 0.62
        case .cooldown: 0.55
        case .rest: 0.45
        case .steady: 0.85
        }
    }
}

struct WorkoutActivity: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let kind: String
    let phaseCurve: [WorkoutPhase]
    let isPreset: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case phaseCurve = "phase_curve"
        case isPreset = "is_preset"
    }
}

struct Place: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let latitude: String
    let longitude: String
    let radiusM: Int
    let privacy: String

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, privacy
        case radiusM = "radius_m"
    }
}

struct ContextSnapshotResponse: Codable, Sendable {
    let id: UUID
    let phase: WorkoutPhase
    let geofenceReference: UUID?

    enum CodingKeys: String, CodingKey {
        case id, phase
        case geofenceReference = "geofence_reference"
    }
}

struct WorkoutPhaseEngine: Sendable {
    let phases: [WorkoutPhase]
    let duration: TimeInterval

    func phase(at elapsed: TimeInterval) -> WorkoutPhase {
        guard !phases.isEmpty else { return .steady }
        let progress = min(0.999_999, max(0, elapsed / max(1, duration)))
        return phases[min(phases.count - 1, Int(progress * Double(phases.count)))]
    }
}

enum FutureQueueReranker {
    static func rerank(
        _ queue: [Track], after currentID: UUID, targetEnergy: Double, limit: Int = 8
    ) -> [Track] {
        guard let current = queue.firstIndex(where: { $0.id == currentID }) else { return queue }
        let start = current + 1
        guard start < queue.count else { return queue }
        let end = min(queue.count, start + max(0, limit))
        var result = queue
        result.replaceSubrange(start..<end, with: queue[start..<end].enumerated().sorted {
            let left = abs(($0.element.energy ?? 0.5) - targetEnergy)
            let right = abs(($1.element.energy ?? 0.5) - targetEnergy)
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element))
        return result
    }
}
