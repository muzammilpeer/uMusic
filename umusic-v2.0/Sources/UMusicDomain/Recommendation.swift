import Foundation

public enum RecommendationReasonCode: String, Codable, CaseIterable, Sendable {
    case coldStartDiversity
    case trackAffinity
    case contextAffinity
    case activityAffinity
    case timeAffinity
    case artistAffinity
    case albumAffinity
    case genreAffinity
    case languageAffinity
    case eraAffinity
    case completionHistory
    case exploration
    case availableOffline
    case timeoutFallback
    case modelRanker
    case modelFallback
}

public enum RecommendationExecutionMode: String, Codable, Sendable { case heuristic, shadow, model, fallback }

public struct RecommendationTrace: Codable, Equatable, Sendable {
    public let mode: RecommendationExecutionMode
    public let modelVersion: String?
    public let featureVersion: String
    public let fallbackCode: String?
    public init(mode: RecommendationExecutionMode, modelVersion: String? = nil, featureVersion: String, fallbackCode: String? = nil) {
        self.mode = mode; self.modelVersion = modelVersion; self.featureVersion = featureVersion; self.fallbackCode = fallbackCode
    }
}

public struct RecommendationProfile: Sendable {
    public let trackAffinities: [UUID: TrackAffinityAggregate]
    public let featureAggregates: [String: FeatureAggregate]
    public let activity: ListeningActivity
    public let localHour: Int
    public init(trackAffinities: [UUID: TrackAffinityAggregate] = [:], featureAggregates: [String: FeatureAggregate] = [:], activity: ListeningActivity = .unknown, localHour: Int = 12) {
        self.trackAffinities = trackAffinities; self.featureAggregates = featureAggregates
        self.activity = activity; self.localHour = min(max(localHour, 0), 23)
    }
}

public struct RecommendedTrack: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { track.id }
    public let track: TrackSummary
    public let score: Double
    public let reasons: [RecommendationReasonCode]
    public init(track: TrackSummary, score: Double, reasons: [RecommendationReasonCode]) {
        self.track = track; self.score = score; self.reasons = reasons
    }
}

public struct RecommendationResult: Codable, Equatable, Sendable {
    public let recommendationID: UUID
    public let engineVersion: String
    public let generatedAt: Date
    public let items: [RecommendedTrack]
    public let usedFallback: Bool
    public let trace: RecommendationTrace?
    public init(recommendationID: UUID = UUID(), engineVersion: String, generatedAt: Date, items: [RecommendedTrack], usedFallback: Bool = false, trace: RecommendationTrace? = nil) {
        self.recommendationID = recommendationID; self.engineVersion = engineVersion
        self.generatedAt = generatedAt; self.items = items; self.usedFallback = usedFallback; self.trace = trace
    }
}

public protocol AutomaticQueueProviding: Sendable {
    func automaticTracks(excluding trackIDs: Set<UUID>, count: Int, at date: Date) async -> [TrackSummary]
}
