import Foundation

public enum RawHistoryRetention: String, Codable, CaseIterable, Sendable, Identifiable {
    case sevenDays, thirtyDays, ninetyDays, oneYear, indefinite
    public var id: String { rawValue }
    public var dayCount: Int? {
        switch self { case .sevenDays: 7; case .thirtyDays: 30; case .ninetyDays: 90; case .oneYear: 365; case .indefinite: nil }
    }
}

public enum LearningEventType: String, Codable, Sendable {
    case sessionStarted, sessionEnded, trackStarted, trackPaused, trackResumed
    case trackSeeked, trackEnded, trackSkipped, technicalFailure, contextChanged
}

public enum PlaybackEndReason: String, Codable, Sendable { case completed, skipped, replaced, stopped, technicalFailure }

public struct PlaybackSession: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let schemaVersion: Int
    public let startedAt: Date
    public var endedAt: Date?
    public init(id: UUID = UUID(), schemaVersion: Int = 1, startedAt: Date, endedAt: Date? = nil) {
        self.id = id; self.schemaVersion = schemaVersion; self.startedAt = startedAt; self.endedAt = endedAt
    }
}

/// Compact, typed event payload. It intentionally has no arbitrary string metadata field.
public struct EventEnvelope: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let schemaVersion: Int
    public let sequence: Int64
    public let sessionID: UUID
    public let type: LearningEventType
    public let occurredAt: Date
    public let monotonicMilliseconds: Int64
    public let trackID: UUID?
    public let positionMilliseconds: Int64?
    public let durationMilliseconds: Int64?
    public let endReason: PlaybackEndReason?

    public init(id: UUID = UUID(), schemaVersion: Int = 1, sequence: Int64, sessionID: UUID, type: LearningEventType, occurredAt: Date, monotonicMilliseconds: Int64, trackID: UUID? = nil, positionMilliseconds: Int64? = nil, durationMilliseconds: Int64? = nil, endReason: PlaybackEndReason? = nil) {
        self.id = id; self.schemaVersion = schemaVersion; self.sequence = sequence
        self.sessionID = sessionID; self.type = type; self.occurredAt = occurredAt
        self.monotonicMilliseconds = max(monotonicMilliseconds, 0); self.trackID = trackID
        self.positionMilliseconds = positionMilliseconds; self.durationMilliseconds = durationMilliseconds
        self.endReason = endReason
    }
}

public struct ContextSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let localHour: Int
    public let weekday: Int
    public let timeZoneSecondsFromGMT: Int
    public let activity: ListeningActivity
    public let activitySource: ActivitySource
    public let activityConfidence: Double
    public let placeClass: CoarsePlaceClass
    public let routeCategory: AudioRouteCategory
    public let networkClass: NetworkClass
    public let lowEnergyMode: Bool
    public let capturedAt: Date

    public init(id: UUID = UUID(), date: Date, calendar: Calendar, activity: ListeningActivity = .unknown, activitySource: ActivitySource = .unknown, activityConfidence: Double = 0, placeClass: CoarsePlaceClass = .unknown, routeCategory: AudioRouteCategory = .unknown, networkClass: NetworkClass = .unknown, lowEnergyMode: Bool = true) {
        self.id = id; self.localHour = calendar.component(.hour, from: date)
        self.weekday = calendar.component(.weekday, from: date)
        self.timeZoneSecondsFromGMT = calendar.timeZone.secondsFromGMT(for: date)
        self.activity = activity
        self.activitySource = activitySource; self.activityConfidence = min(max(activityConfidence, 0), 1)
        self.placeClass = placeClass; self.routeCategory = routeCategory; self.networkClass = networkClass
        self.lowEnergyMode = lowEnergyMode; self.capturedAt = date
    }

    private enum CodingKeys: String, CodingKey { case id, localHour, weekday, timeZoneSecondsFromGMT, activity, activitySource, activityConfidence, placeClass, routeCategory, networkClass, lowEnergyMode, capturedAt }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        localHour = try values.decode(Int.self, forKey: .localHour)
        weekday = try values.decode(Int.self, forKey: .weekday)
        timeZoneSecondsFromGMT = try values.decode(Int.self, forKey: .timeZoneSecondsFromGMT)
        activity = try values.decode(ListeningActivity.self, forKey: .activity)
        activitySource = try values.decodeIfPresent(ActivitySource.self, forKey: .activitySource) ?? .unknown
        activityConfidence = try values.decodeIfPresent(Double.self, forKey: .activityConfidence) ?? 0
        placeClass = try values.decodeIfPresent(CoarsePlaceClass.self, forKey: .placeClass) ?? .unknown
        routeCategory = try values.decodeIfPresent(AudioRouteCategory.self, forKey: .routeCategory) ?? .unknown
        networkClass = try values.decodeIfPresent(NetworkClass.self, forKey: .networkClass) ?? .unknown
        lowEnergyMode = try values.decodeIfPresent(Bool.self, forKey: .lowEnergyMode) ?? true
        capturedAt = try values.decodeIfPresent(Date.self, forKey: .capturedAt) ?? .distantPast
    }
}

public struct PlaybackObservation: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let trackID: UUID
    public let contextID: UUID
    public let startedAt: Date
    public var endedAt: Date?
    public var listenedMilliseconds: Int64
    public var durationMilliseconds: Int64?
    public var exposureCount: Int
    public var seekCount: Int
    public var endReason: PlaybackEndReason?

    public init(id: UUID = UUID(), sessionID: UUID, trackID: UUID, contextID: UUID, startedAt: Date, endedAt: Date? = nil, listenedMilliseconds: Int64 = 0, durationMilliseconds: Int64? = nil, exposureCount: Int = 1, seekCount: Int = 0, endReason: PlaybackEndReason? = nil) {
        self.id = id; self.sessionID = sessionID; self.trackID = trackID; self.contextID = contextID
        self.startedAt = startedAt; self.endedAt = endedAt; self.listenedMilliseconds = max(listenedMilliseconds, 0)
        self.durationMilliseconds = durationMilliseconds; self.exposureCount = max(exposureCount, 0)
        self.seekCount = max(seekCount, 0); self.endReason = endReason
    }
}

public struct TrackAffinityAggregate: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { trackID }
    public let trackID: UUID
    public var exposures: Int
    public var completions: Int
    public var skips: Int
    public var listenedMilliseconds: Int64
    public var lastUpdatedAt: Date
    public init(trackID: UUID, exposures: Int = 0, completions: Int = 0, skips: Int = 0, listenedMilliseconds: Int64 = 0, lastUpdatedAt: Date) {
        self.trackID = trackID; self.exposures = max(exposures, 0); self.completions = max(completions, 0)
        self.skips = max(skips, 0); self.listenedMilliseconds = max(listenedMilliseconds, 0); self.lastUpdatedAt = lastUpdatedAt
    }
}

public struct FeatureAggregate: Codable, Equatable, Sendable, Identifiable {
    public var id: String { featureKey }
    public let featureKey: String
    public var exposures: Int
    public var completions: Int
    public var listenedMilliseconds: Int64
    public var lastUpdatedAt: Date
    public init(featureKey: String, exposures: Int = 0, completions: Int = 0, listenedMilliseconds: Int64 = 0, lastUpdatedAt: Date) {
        self.featureKey = featureKey; self.exposures = max(exposures, 0); self.completions = max(completions, 0)
        self.listenedMilliseconds = max(listenedMilliseconds, 0); self.lastUpdatedAt = lastUpdatedAt
    }
}

public enum ConsentStatus: String, Codable, Sendable { case granted, denied, revoked }
public struct ConsentRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let signal: String
    public let status: ConsentStatus
    public let policyVersion: Int
    public let recordedAt: Date
    public init(id: UUID = UUID(), signal: String, status: ConsentStatus, policyVersion: Int, recordedAt: Date) {
        self.id = id; self.signal = signal; self.status = status; self.policyVersion = policyVersion; self.recordedAt = recordedAt
    }
}

public struct LearningSnapshot: Codable, Equatable, Sendable {
    public let retention: RawHistoryRetention
    public let eventCount: Int
    public let observationCount: Int
    public let aggregateCount: Int
    public let lastReducedSequence: Int64
    public init(retention: RawHistoryRetention, eventCount: Int, observationCount: Int, aggregateCount: Int, lastReducedSequence: Int64) {
        self.retention = retention; self.eventCount = eventCount; self.observationCount = observationCount
        self.aggregateCount = aggregateCount; self.lastReducedSequence = lastReducedSequence
    }
}

public enum PlaybackLearningTransition: Sendable {
    case started(track: TrackSummary, positionSeconds: Double)
    case resumed(positionSeconds: Double)
    case paused(positionSeconds: Double)
    case seeked(fromSeconds: Double, toSeconds: Double)
    case ended(positionSeconds: Double, durationSeconds: Double?, reason: PlaybackEndReason)
    case checkpoint(positionSeconds: Double, durationSeconds: Double?)
    case technicalFailure(positionSeconds: Double)
}

public protocol PlaybackLearningRecording: Sendable {
    func record(_ transition: PlaybackLearningTransition) async
    func flush() async
}
