import Foundation
import Testing
import UMusicDomain
@testable import UMusicLearning

private func learningURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appending(path: "umusic-learning-tests").appending(path: "\(name).json")
}

private let learningTrack = TrackSummary(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, title: "Safe title", artist: "Safe artist", durationSeconds: 200)

@Test("A fifteen-second checkpoint survives a simulated process restart without tick events")
func learningCrashCheckpoint() async throws {
    let url = learningURL()
    let store = LocalLearningStore(url: url)
    await store.record(.started(track: learningTrack, positionSeconds: 0))
    await store.record(.checkpoint(positionSeconds: 16, durationSeconds: 200))
    let relaunched = LocalLearningStore(url: url)
    let snapshot = await relaunched.learningSnapshot()
    #expect(snapshot.observationCount == 1)
    #expect(snapshot.eventCount == 1) // the relaunched session-start event only; checkpoints create no tick event
    #expect((try Data(contentsOf: url)).count < 50_000)
}

@Test("Stable event IDs deduplicate and reducer checkpoints are idempotent across restart")
func learningDeduplicationAndReducerRestart() async throws {
    let url = learningURL()
    let store = LocalLearningStore(url: url)
    let event = EventEnvelope(id: UUID(), sequence: 7, sessionID: UUID(), type: .trackStarted, occurredAt: Date(), monotonicMilliseconds: 1, trackID: learningTrack.id)
    try await store.ingestEventEnvelopes([event, event])
    #expect(await store.learningSnapshot().eventCount == 2) // one session start plus one deduplicated imported event

    await store.record(.started(track: learningTrack, positionSeconds: 0))
    await store.record(.ended(positionSeconds: 195, durationSeconds: 200, reason: .completed))
    await store.flush()
    let aggregateCount = await store.learningSnapshot().aggregateCount
    #expect(aggregateCount >= 4)
    let relaunched = LocalLearningStore(url: url)
    await relaunched.flush()
    let snapshot = await relaunched.learningSnapshot()
    #expect(snapshot.aggregateCount == aggregateCount)
}

@Test("Every retention preset persists; delete history and Reset Learning have distinct scope")
func retentionDeletionAndReset() async throws {
    let url = learningURL()
    let store = LocalLearningStore(url: url)
    for retention in RawHistoryRetention.allCases {
        try await store.setRawHistoryRetention(retention)
        #expect(await store.learningSnapshot().retention == retention)
    }
    await store.record(.started(track: learningTrack, positionSeconds: 0))
    await store.record(.ended(positionSeconds: 190, durationSeconds: 200, reason: .completed))
    await store.flush()
    try await store.deleteHistory()
    var snapshot = await store.learningSnapshot()
    #expect(snapshot.eventCount == 0 && snapshot.observationCount == 0)
    #expect(snapshot.aggregateCount >= 4)
    try await store.resetLearning()
    snapshot = await store.learningSnapshot()
    #expect(snapshot.aggregateCount == 0)
}

@Test("Expiry reduces before batch deletion and repeated semantic transitions coalesce")
func expiryAndCoalescing() async throws {
    let store = LocalLearningStore(url: learningURL())
    await store.record(.started(track: learningTrack, positionSeconds: 0))
    await store.record(.resumed(positionSeconds: 1))
    await store.record(.resumed(positionSeconds: 2))
    await store.record(.ended(positionSeconds: 190, durationSeconds: 200, reason: .completed))
    await store.flush()
    #expect(await store.learningSnapshot().eventCount == 4) // session, start, one coalesced resume, end
    try await store.setRawHistoryRetention(.sevenDays)
    try await store.compact(now: Date().addingTimeInterval(8 * 86_400))
    let snapshot = await store.learningSnapshot()
    #expect(snapshot.observationCount == 0)
    #expect(snapshot.aggregateCount >= 4)
}

@Test("Technical failures count exposure but never become preference skips")
func technicalFailureIsNotDislike() async throws {
    let store = LocalLearningStore(url: learningURL())
    await store.record(.started(track: learningTrack, positionSeconds: 0))
    await store.record(.technicalFailure(positionSeconds: 5))
    await store.flush()
    let export = try await store.exportSanitized()
    let text = try String(contentsOf: export, encoding: .utf8)
    #expect(text.contains("technicalFailure"))
    #expect(text.contains("\"skips\" : 0"))
}

@Test("Schema zero migrates and a future schema is preserved without overwrite")
func learningSchemaSafety() async throws {
    let migratedURL = learningURL()
    let initial = LocalLearningStore(url: migratedURL)
    try await initial.setRawHistoryRetention(.thirtyDays)
    var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: migratedURL)) as? [String: Any])
    json["schemaVersion"] = 0
    try JSONSerialization.data(withJSONObject: json).write(to: migratedURL, options: .atomic)
    let migrated = LocalLearningStore(url: migratedURL)
    try await migrated.setRawHistoryRetention(.sevenDays)
    let migratedJSON = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: migratedURL)) as? [String: Any])
    #expect(migratedJSON["schemaVersion"] as? Int == 1)

    let futureURL = learningURL()
    let futureData = Data("{\"schemaVersion\":999}".utf8)
    try futureData.write(to: futureURL, options: .atomic)
    let future = LocalLearningStore(url: futureURL)
    await #expect(throws: LearningStoreError.unsupportedSchema) { try await future.setRawHistoryRetention(.sevenDays) }
    #expect(try Data(contentsOf: futureURL) == futureData)
}

@Test("Sanitized export contains typed data and excludes sensitive field vocabulary")
func sanitizedLearningExport() async throws {
    let store = LocalLearningStore(url: learningURL())
    await store.record(.started(track: learningTrack, positionSeconds: 0))
    await store.record(.paused(positionSeconds: 20))
    let exportURL = try await store.exportSanitized()
    let exported = try String(contentsOf: exportURL, encoding: .utf8).lowercased()
    #expect(exported.contains("sanitized"))
    for forbidden in ["password", "access_token", "server_url", "latitude", "longitude", "file_path", "username"] {
        #expect(!exported.contains(forbidden))
    }
}

@Test("Clock rollback cannot create a negative monotonic offset")
func learningClockRollbackSafety() {
    let event = EventEnvelope(sequence: 1, sessionID: UUID(), type: .sessionStarted, occurredAt: Date.distantPast, monotonicMilliseconds: -500)
    #expect(event.monotonicMilliseconds == 0)
}
