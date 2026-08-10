import Foundation

public enum ResearchExportKind: String, Codable, Sendable { case sanitized, full }

public struct ResearchExportPreview: Codable, Equatable, Sendable {
    public let confirmationID: UUID
    public let eventCount: Int
    public let observationCount: Int
    public let includesTrackMetadata: Bool
    public let sensitiveCategories: [String]
    public let expiresAt: Date
    public init(confirmationID: UUID = UUID(), eventCount: Int, observationCount: Int, includesTrackMetadata: Bool, sensitiveCategories: [String], expiresAt: Date) {
        self.confirmationID = confirmationID; self.eventCount = eventCount; self.observationCount = observationCount
        self.includesTrackMetadata = includesTrackMetadata; self.sensitiveCategories = sensitiveCategories; self.expiresAt = expiresAt
    }
}

public struct ResearchExportManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let exportKind: ResearchExportKind
    public let generatedAt: Date
    public let files: [String]
    public let recordCounts: [String: Int]
    public let excludedFields: [String]
    public init(schemaVersion: Int, exportKind: ResearchExportKind, generatedAt: Date, files: [String], recordCounts: [String: Int], excludedFields: [String]) {
        self.schemaVersion = schemaVersion; self.exportKind = exportKind; self.generatedAt = generatedAt
        self.files = files; self.recordCounts = recordCounts; self.excludedFields = excludedFields
    }
}

public enum ResearchExportError: Error, Equatable { case confirmationRequired, confirmationExpired, insufficientDisk, cancelled, malformedPackage }

public protocol ResearchExportEncrypting: Sendable {
    func encrypt(packageAt source: URL, destination: URL) async throws -> URL
}

public struct TrainingExample: Codable, Equatable, Sendable {
    public let observationID: UUID
    public let sessionID: UUID
    public let trackID: UUID
    public let startedAt: Date
    public let localHour: Int
    public let weekday: Int
    public let activity: ListeningActivity
    public let completionLabel: Bool
    public let skipLabel: Bool
    public let listenedRatio: Double
    public init(observationID: UUID, sessionID: UUID, trackID: UUID, startedAt: Date, localHour: Int, weekday: Int, activity: ListeningActivity, completionLabel: Bool, skipLabel: Bool, listenedRatio: Double) {
        self.observationID = observationID; self.sessionID = sessionID; self.trackID = trackID; self.startedAt = startedAt
        self.localHour = localHour; self.weekday = weekday; self.activity = activity
        self.completionLabel = completionLabel; self.skipLabel = skipLabel; self.listenedRatio = min(max(listenedRatio, 0), 1)
    }
}

public struct TrainingDatasetSplit: Codable, Equatable, Sendable {
    public let training: [TrainingExample]
    public let validation: [TrainingExample]
    public let test: [TrainingExample]
    public init(training: [TrainingExample], validation: [TrainingExample], test: [TrainingExample]) { self.training = training; self.validation = validation; self.test = test }
}

public struct BaselineMetrics: Codable, Equatable, Sendable {
    public let exampleCount: Int
    public let majorityAccuracy: Double
    public let completionRate: Double
    public init(exampleCount: Int, majorityAccuracy: Double, completionRate: Double) { self.exampleCount = exampleCount; self.majorityAccuracy = majorityAccuracy; self.completionRate = completionRate }
}
