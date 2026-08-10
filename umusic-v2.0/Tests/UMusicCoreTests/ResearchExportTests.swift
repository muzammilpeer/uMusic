import Foundation
import Testing
import UMusicDomain
@testable import UMusicLearning

private func exportObservation(_ index: Int, session: UUID, context: UUID, date: Date) -> PlaybackObservation {
    .init(id: UUID(), sessionID: session, trackID: UUID(), contextID: context, startedAt: date.addingTimeInterval(Double(index)), endedAt: date.addingTimeInterval(Double(index + 1)), listenedMilliseconds: Int64(index % 100) * 1_000, durationMilliseconds: 100_000, endReason: index.isMultiple(of: 3) ? .completed : .skipped)
}

@Test("Streaming package round-trips its schema and large JSONL record count")
func researchLargeExportRoundTrip() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let session = UUID(), contextID = UUID(), start = Date(timeIntervalSince1970: 2_000_000_000)
    let observations = (0..<20_000).map { exportObservation($0, session: session, context: contextID, date: start) }
    let records = ResearchExportRecords(events: [], sessions: [], observations: observations, contexts: [], aggregates: [], featureAggregates: [], consents: [], tracks: [])
    let package = try await ResearchPackageWriter.write(records: records, kind: .sanitized, root: root, availableCapacityBytes: 100_000_000)
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(ResearchExportManifest.self, from: Data(contentsOf: package.appending(path: "manifest.json")))
    #expect(manifest.schemaVersion == 1)
    #expect(manifest.recordCounts["observations.jsonl"] == 20_000)
    let bytes = try Data(contentsOf: package.appending(path: "observations.jsonl"))
    #expect(bytes.filter { $0 == 0x0A }.count == 20_000)
    try? FileManager.default.removeItem(at: root)
}

@Test("Low disk and cancellation remove incomplete output")
func researchExportFailureCleanup() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let records = ResearchExportRecords(events: [], sessions: [], observations: [], contexts: [], aggregates: [], featureAggregates: [], consents: [], tracks: [])
    await #expect(throws: ResearchExportError.insufficientDisk) { try await ResearchPackageWriter.write(records: records, kind: .sanitized, root: root, availableCapacityBytes: 1) }
    let session = UUID(), context = UUID(), start = Date()
    let many = (0..<10_000).map { exportObservation($0, session: session, context: context, date: start) }
    let cancellableRecords = ResearchExportRecords(events: [], sessions: [], observations: many, contexts: [], aggregates: [], featureAggregates: [], consents: [], tracks: [])
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await ResearchPackageWriter.write(records: cancellableRecords, kind: .sanitized, root: root, availableCapacityBytes: 100_000_000)
    }
    await #expect(throws: (any Error).self) { try await task.value }
    let exportRoot = root.appending(path: "uMusicResearchExports")
    #expect(((try? FileManager.default.contentsOfDirectory(atPath: exportRoot.path)) ?? []).isEmpty)
    try? FileManager.default.removeItem(at: root)
}

@Test("Exact export discard cannot delete outside the protected export root")
func exactExportDiscard() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "discard-\(UUID())")
    let records = ResearchExportRecords(events: [], sessions: [], observations: [], contexts: [], aggregates: [], featureAggregates: [], consents: [], tracks: [])
    let package = try await ResearchPackageWriter.write(records: records, kind: .sanitized, root: root)
    #expect(FileManager.default.fileExists(atPath: package.path))
    ResearchPackageWriter.discard(package, root: root)
    #expect(!FileManager.default.fileExists(atPath: package.path))
    let outside = root.appending(path: "keep.umusicresearch")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    ResearchPackageWriter.discard(outside, root: root)
    #expect(FileManager.default.fileExists(atPath: outside.path))
    try? FileManager.default.removeItem(at: root)
}

@Test("Sanitized manifest carries the denylist and full export requires a fresh preview")
func researchRedactionAndFullConfirmation() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "learning-export-\(UUID()).json")
    let store = LocalLearningStore(url: url)
    await #expect(throws: ResearchExportError.confirmationRequired) { try await store.exportResearch(.full, confirmationID: nil) }
    let preview = await store.previewFullResearchExport()
    let full = try await store.exportResearch(.full, confirmationID: preview.confirmationID)
    #expect(FileManager.default.fileExists(atPath: full.appending(path: "tracks.jsonl").path))
    let sanitized = try await store.exportResearch(.sanitized, confirmationID: nil)
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(ResearchExportManifest.self, from: Data(contentsOf: sanitized.appending(path: "manifest.json")))
    #expect(Set(manifest.excludedFields) == Set(ResearchPackageWriter.forbiddenSanitizedTerms))
    #expect(!manifest.files.contains("tracks.jsonl"))
    await store.cleanupResearchExports()
    #expect(!FileManager.default.fileExists(atPath: full.path))
    try? FileManager.default.removeItem(at: url)
}

@Test("Sanitized package drops arbitrary feature and consent strings")
func researchSanitizedPayloadRedaction() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let unsafeFeature = FeatureAggregate(featureKey: "artist:password server_url /private/file_path", exposures: 1, lastUpdatedAt: Date())
    let unsafeConsent = ConsentRecord(signal: "username_token_coordinate", status: .granted, policyVersion: 1, recordedAt: Date())
    let records = ResearchExportRecords(events: [], sessions: [], observations: [], contexts: [], aggregates: [], featureAggregates: [unsafeFeature], consents: [unsafeConsent], tracks: [])
    let package = try await ResearchPackageWriter.write(records: records, kind: .sanitized, root: root, availableCapacityBytes: 10_000_000)
    var combined = ""
    for file in (try FileManager.default.contentsOfDirectory(atPath: package.path)) where file != "manifest.json" { combined += (try? String(contentsOf: package.appending(path: file), encoding: .utf8)) ?? "" }
    for term in ResearchPackageWriter.forbiddenSanitizedTerms { #expect(!combined.lowercased().contains(term)) }
    try? FileManager.default.removeItem(at: root)
}

@Test("Features are deterministic, chronologically split by whole session, and baseline metrics are bounded")
func trainingFeatureReproducibilityAndLeakage() {
    let start = Date(timeIntervalSince1970: 2_000_000_000), contextID = UUID()
    let context = ContextSnapshot(id: contextID, date: start, calendar: Calendar(identifier: .gregorian), activity: .focus)
    let sessions = [UUID(), UUID(), UUID(), UUID()]
    let observations = sessions.enumerated().flatMap { offset, session in (0..<3).map { exportObservation($0, session: session, context: contextID, date: start.addingTimeInterval(Double(offset * 100))) } }
    let first = TrainingFeatureBuilder.build(observations: observations.shuffled(), contexts: [context])
    let second = TrainingFeatureBuilder.build(observations: observations.reversed(), contexts: [context])
    #expect(first == second)
    let split = TrainingFeatureBuilder.chronologicalSplit(first)
    let trainingSessions = Set(split.training.map(\.sessionID)), validationSessions = Set(split.validation.map(\.sessionID)), testSessions = Set(split.test.map(\.sessionID))
    #expect(trainingSessions.isDisjoint(with: validationSessions) && trainingSessions.isDisjoint(with: testSessions) && validationSessions.isDisjoint(with: testSessions))
    #expect((split.training.last?.startedAt ?? .distantPast) <= (split.test.first?.startedAt ?? .distantFuture))
    let metrics = TrainingFeatureBuilder.majorityBaseline(first)
    #expect(metrics.exampleCount == observations.count)
    #expect((0.5...1).contains(metrics.majorityAccuracy))
}
