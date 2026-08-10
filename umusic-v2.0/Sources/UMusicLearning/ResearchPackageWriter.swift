import Foundation
import UMusicDomain
import UMusicSupport

public struct ResearchExportRecords: Sendable {
    public let events: [EventEnvelope]
    public let sessions: [PlaybackSession]
    public let observations: [PlaybackObservation]
    public let contexts: [ContextSnapshot]
    public let aggregates: [TrackAffinityAggregate]
    public let featureAggregates: [FeatureAggregate]
    public let consents: [ConsentRecord]
    public let tracks: [TrackSummary]
    public init(events: [EventEnvelope], sessions: [PlaybackSession], observations: [PlaybackObservation], contexts: [ContextSnapshot], aggregates: [TrackAffinityAggregate], featureAggregates: [FeatureAggregate], consents: [ConsentRecord], tracks: [TrackSummary]) {
        self.events = events; self.sessions = sessions; self.observations = observations; self.contexts = contexts
        self.aggregates = aggregates; self.featureAggregates = featureAggregates; self.consents = consents; self.tracks = tracks
    }
}

public enum ResearchPackageWriter {
    public static let schemaVersion = 1
    public static let forbiddenSanitizedTerms = ["password", "token", "server_url", "username", "coordinate", "latitude", "longitude", "file_path", "healthkit_raw", "accessory_identifier"]

    public static func write(records: ResearchExportRecords, kind: ResearchExportKind, root: URL = FileManager.default.temporaryDirectory, availableCapacityBytes: Int64? = nil) async throws -> URL {
        let interval = PerformanceSignposts.begin("ResearchExport"); defer { PerformanceSignposts.end(interval) }
        let manager = FileManager.default
        let exportRoot = root.appending(path: "uMusicResearchExports", directoryHint: .isDirectory)
        try manager.createDirectory(at: exportRoot, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let estimated = Int64(max(records.events.count + records.observations.count + records.contexts.count + records.tracks.count, 1)) * 1_024
        let available = availableCapacityBytes ?? ((try? exportRoot.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? Int64.max)
        guard available > estimated + 1_048_576 else { throw ResearchExportError.insufficientDisk }
        let package = exportRoot.appending(path: "umusic-\(kind.rawValue)-\(UUID().uuidString).umusicresearch", directoryHint: .isDirectory)
        try manager.createDirectory(at: package, withIntermediateDirectories: false, attributes: [.protectionKey: FileProtectionType.complete])
        do {
            var counts: [String: Int] = [:], files: [String] = []
            try await jsonLines(records.events, name: "events.jsonl", in: package, files: &files, counts: &counts)
            try await jsonLines(records.observations, name: "observations.jsonl", in: package, files: &files, counts: &counts)
            try await jsonLines(records.contexts, name: "contexts.jsonl", in: package, files: &files, counts: &counts)
            try await jsonLines(records.aggregates, name: "track-aggregates.jsonl", in: package, files: &files, counts: &counts)
            let exportedFeatures = kind == .sanitized ? records.featureAggregates.filter { $0.featureKey.hasPrefix("activity:") || $0.featureKey.hasPrefix("time:") || $0.featureKey.hasPrefix("era:") } : records.featureAggregates
            try await jsonLines(exportedFeatures, name: "feature-aggregates.jsonl", in: package, files: &files, counts: &counts)
            try await jsonLines(kind == .sanitized ? [] : records.consents, name: "consents.jsonl", in: package, files: &files, counts: &counts)
            if kind == .full {
                try await jsonLines(records.sessions, name: "sessions.jsonl", in: package, files: &files, counts: &counts)
                try await jsonLines(records.tracks, name: "tracks.jsonl", in: package, files: &files, counts: &counts)
            }
            let examples = TrainingFeatureBuilder.build(observations: records.observations, contexts: records.contexts)
            try await csv(examples, in: package, files: &files, counts: &counts)
            let manifest = ResearchExportManifest(schemaVersion: schemaVersion, exportKind: kind, generatedAt: Date(), files: files.sorted(), recordCounts: counts, excludedFields: kind == .sanitized ? forbiddenSanitizedTerms : [])
            try protectedWrite(try encoder.encode(manifest), to: package.appending(path: "manifest.json"))
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: package.path)
            return package
        } catch {
            try? manager.removeItem(at: package)
            if error is CancellationError { throw ResearchExportError.cancelled }
            throw error
        }
    }

    public static func cleanup(root: URL = FileManager.default.temporaryDirectory, olderThan date: Date = Date().addingTimeInterval(-86_400)) {
        let exportRoot = root.appending(path: "uMusicResearchExports", directoryHint: .isDirectory)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in urls where ((try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < date { try? FileManager.default.removeItem(at: url) }
    }

    public static func discard(_ package: URL, root: URL = FileManager.default.temporaryDirectory) {
        let exportRoot = root.appending(path: "uMusicResearchExports", directoryHint: .isDirectory).standardizedFileURL
        let candidate = package.standardizedFileURL
        guard candidate.deletingLastPathComponent() == exportRoot,
              candidate.pathExtension == "umusicresearch" else { return }
        try? FileManager.default.removeItem(at: candidate)
    }

    private static func jsonLines<T: Encodable>(_ values: [T], name: String, in package: URL, files: inout [String], counts: inout [String: Int]) async throws {
        let url = package.appending(path: name); FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        for (index, value) in values.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            var data = try encoder.encode(value); data.append(0x0A); try handle.write(contentsOf: data)
        }
        files.append(name); counts[name] = values.count
    }

    private static func csv(_ values: [TrainingExample], in package: URL, files: inout [String], counts: inout [String: Int]) async throws {
        let name = "training-features.csv", url = package.appending(path: name)
        let iso = ISO8601DateFormatter()
        FileManager.default.createFile(atPath: url.path, contents: Data("observation_id,session_id,track_id,started_at,local_hour,weekday,activity,completion,skip,listened_ratio\n".utf8), attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: url); try handle.seekToEnd(); defer { try? handle.close() }
        for (index, value) in values.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            let row = "\(value.observationID.uuidString),\(value.sessionID.uuidString),\(value.trackID.uuidString),\(iso.string(from: value.startedAt)),\(value.localHour),\(value.weekday),\(value.activity.rawValue),\(value.completionLabel ? 1 : 0),\(value.skipLabel ? 1 : 0),\(value.listenedRatio)\n"
            try handle.write(contentsOf: Data(row.utf8))
        }
        files.append(name); counts[name] = values.count
    }

    private static func protectedWrite(_ data: Data, to url: URL) throws { try data.write(to: url, options: [.atomic, .completeFileProtection]); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
    private static let encoder: JSONEncoder = { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return value }()
}

public enum TrainingFeatureBuilder {
    public static func build(observations: [PlaybackObservation], contexts: [ContextSnapshot]) -> [TrainingExample] {
        let contextByID = Dictionary(uniqueKeysWithValues: contexts.map { ($0.id, $0) })
        return observations.sorted { $0.startedAt == $1.startedAt ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt }.map { observation in
            let context = contextByID[observation.contextID]
            let ratio = observation.durationMilliseconds.flatMap { $0 > 0 ? Double(observation.listenedMilliseconds) / Double($0) : nil } ?? 0
            return TrainingExample(observationID: observation.id, sessionID: observation.sessionID, trackID: observation.trackID, startedAt: observation.startedAt, localHour: context?.localHour ?? 12, weekday: context?.weekday ?? 1, activity: context?.activity ?? .unknown, completionLabel: observation.endReason == .completed, skipLabel: observation.endReason == .skipped, listenedRatio: ratio)
        }
    }

    public static func chronologicalSplit(_ examples: [TrainingExample], trainingFraction: Double = 0.7, validationFraction: Double = 0.15) -> TrainingDatasetSplit {
        let groups = Dictionary(grouping: examples, by: \.sessionID).values.sorted { ($0.map(\.startedAt).min() ?? .distantPast) < ($1.map(\.startedAt).min() ?? .distantPast) }
        let total = groups.reduce(0) { $0 + $1.count }, trainingTarget = Int(Double(total) * min(max(trainingFraction, 0), 1)), validationTarget = Int(Double(total) * min(max(validationFraction, 0), 1))
        var training: [TrainingExample] = [], validation: [TrainingExample] = [], test: [TrainingExample] = []
        for group in groups {
            if training.count < trainingTarget { training += group }
            else if validation.count < validationTarget { validation += group }
            else { test += group }
        }
        return .init(training: training, validation: validation, test: test)
    }

    public static func majorityBaseline(_ examples: [TrainingExample]) -> BaselineMetrics {
        guard !examples.isEmpty else { return .init(exampleCount: 0, majorityAccuracy: 0, completionRate: 0) }
        let completed = examples.filter(\.completionLabel).count, rate = Double(completed) / Double(examples.count)
        return .init(exampleCount: examples.count, majorityAccuracy: max(rate, 1 - rate), completionRate: rate)
    }
}
