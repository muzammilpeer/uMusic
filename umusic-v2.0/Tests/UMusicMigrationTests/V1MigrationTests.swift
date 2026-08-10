import Foundation
import Testing
import UMusicDomain
@testable import UMusicMigration

private func fixture() throws -> (URL, URL, [V1Track], [V1ListeningEvent]) {
    let base = FileManager.default.temporaryDirectory.appending(path: "migration-test-\(UUID())")
    let source = base.appending(path: "v1"), destination = base.appending(path: "v2")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let tracks = [V1Track(id: UUID(), title: "Old Song", artist: .init(id: UUID(), name: "Artist"), album: .init(id: UUID(), title: "Album"), durationMS: 123_000, genres: ["Rock"], streamPath: "/api/private")]
    let events = [V1ListeningEvent(clientEventID: UUID(), playbackID: UUID(), trackID: tracks[0].id, eventType: "completed", clientTimestamp: Date(timeIntervalSince1970: 2_000_000_000), positionMS: 123_000, durationMS: 123_000, listenedMSDelta: 123_000, offline: true)]
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(tracks).write(to: source.appending(path: V1MigrationFile.catalog.rawValue), options: .atomic)
    try encoder.encode(tracks).write(to: source.appending(path: V1MigrationFile.queue.rawValue), options: .atomic)
    try encoder.encode(events).write(to: source.appending(path: V1MigrationFile.history.rawValue), options: .atomic)
    try encoder.encode(V1Settings(lowEnergyMode: true, wifiOnly: true, chargingOnly: false, quotaBytes: 500_000_000)).write(to: source.appending(path: V1MigrationFile.settings.rawValue), options: .atomic)
    return (source, destination, tracks, events)
}

@Test("Copy-first migration maps IDs, validates checksums, and never alters v1")
func copyFirstMigration() async throws {
    let (source, destination, tracks, events) = try fixture(); defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let before = try Data(contentsOf: source.appending(path: V1MigrationFile.catalog.rawValue))
    let id = UUID(), adapter = V1MigrationAdapter()
    let result = try await adapter.migrate(source: DirectoryV1MigrationSource(root: source), destinationRoot: destination, migrationID: id, availableCapacityBytes: 10_000_000)
    #expect(result.packageURL.pathExtension == "ready")
    #expect(result.manifest.counts["tracks"] == tracks.count)
    #expect(result.manifest.counts["history_events"] == events.count)
    #expect(result.manifest.identityMappings["track:\(tracks[0].id.uuidString.lowercased())"] == tracks[0].id.uuidString.lowercased())
    #expect(result.manifest.unsupportedFields.contains("credentials"))
    #expect(try Data(contentsOf: source.appending(path: V1MigrationFile.catalog.rawValue)) == before)
    #expect(FileManager.default.fileExists(atPath: source.path))
}

@Test("Interrupted migration resumes from its checkpoint")
func interruptionAndRetry() async throws {
    let (source, destination, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let id = UUID(), adapter = V1MigrationAdapter(), reader = DirectoryV1MigrationSource(root: source)
    await #expect(throws: V1MigrationError.interrupted) { try await adapter.migrate(source: reader, destinationRoot: destination, migrationID: id, availableCapacityBytes: 10_000_000, interruptAfterPhase: 2) }
    let staging = destination.appending(path: "migration-\(id.uuidString.lowercased()).staging")
    #expect(FileManager.default.fileExists(atPath: staging.appending(path: "checkpoint.json").path))
    let result = try await adapter.migrate(source: reader, destinationRoot: destination, migrationID: id, availableCapacityBytes: 10_000_000)
    #expect(result.manifest.state == "ready")
}

@Test("Corruption, changed source, and low storage fail without touching v1")
func recoveryFailures() async throws {
    let (source, destination, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let adapter = V1MigrationAdapter()
    await #expect(throws: V1MigrationError.insufficientDisk) { try await adapter.migrate(source: DirectoryV1MigrationSource(root: source), destinationRoot: destination, migrationID: UUID(), availableCapacityBytes: 1) }
    try Data("not-json".utf8).write(to: source.appending(path: V1MigrationFile.catalog.rawValue), options: .atomic)
    await #expect(throws: V1MigrationError.corruptSource("catalog.json")) { try await adapter.migrate(source: DirectoryV1MigrationSource(root: source), destinationRoot: destination, migrationID: UUID(), availableCapacityBytes: 10_000_000) }
}

@Test("Changed source and corrupted completed output are rejected")
func integrityRecovery() async throws {
    let (source, destination, tracks, _) = try fixture(); defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let id = UUID(), adapter = V1MigrationAdapter(), reader = DirectoryV1MigrationSource(root: source)
    await #expect(throws: V1MigrationError.interrupted) { try await adapter.migrate(source: reader, destinationRoot: destination, migrationID: id, availableCapacityBytes: 10_000_000, interruptAfterPhase: 1) }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(tracks + [V1Track(id: UUID(), title: "Changed", artist: .init(id: UUID(), name: "Artist"), durationMS: 1_000)]).write(to: source.appending(path: V1MigrationFile.catalog.rawValue), options: .atomic)
    await #expect(throws: V1MigrationError.sourceChanged) { try await adapter.migrate(source: reader, destinationRoot: destination, migrationID: id, availableCapacityBytes: 10_000_000) }

    let secondID = UUID(), second = try fixture(); defer { try? FileManager.default.removeItem(at: second.0.deletingLastPathComponent()) }
    let completed = try await adapter.migrate(source: DirectoryV1MigrationSource(root: second.0), destinationRoot: second.1, migrationID: secondID, availableCapacityBytes: 10_000_000)
    try Data("corrupt".utf8).write(to: completed.packageURL.appending(path: "catalog-v2.json"), options: .atomic)
    await #expect(throws: V1MigrationError.outputValidationFailed) { try await adapter.migrate(source: DirectoryV1MigrationSource(root: second.0), destinationRoot: second.1, migrationID: secondID, availableCapacityBytes: 10_000_000) }
}

@Test("Rollback requires confirmation and deletes only incomplete staging")
func rollbackScope() async throws {
    let (source, destination, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let id = UUID(), adapter = V1MigrationAdapter(), reader = DirectoryV1MigrationSource(root: source)
    await #expect(throws: V1MigrationError.interrupted) { try await adapter.migrate(source: reader, destinationRoot: destination, migrationID: id, availableCapacityBytes: 10_000_000, interruptAfterPhase: 1) }
    await #expect(throws: V1MigrationError.confirmationRequired) { try await adapter.rollbackIncomplete(migrationID: id, destinationRoot: destination, confirmed: false) }
    try await adapter.rollbackIncomplete(migrationID: id, destinationRoot: destination, confirmed: true)
    #expect(!FileManager.default.fileExists(atPath: destination.appending(path: "migration-\(id.uuidString.lowercased()).staging").path))
    let completed = try await adapter.migrate(source: reader, destinationRoot: destination, migrationID: id, availableCapacityBytes: 10_000_000)
    await #expect(throws: V1MigrationError.completedMigrationCannotRollback) { try await adapter.rollbackIncomplete(migrationID: id, destinationRoot: destination, confirmed: true) }
    #expect(FileManager.default.fileExists(atPath: completed.packageURL.path))
}

private struct DeniedSource: V1MigrationSource {
    func read(_ file: V1MigrationFile) async throws -> Data? { throw CocoaError(.fileReadNoPermission) }
}

@Test("Source permission failures propagate without creating a ready package")
func permissionFailure() async {
    let destination = FileManager.default.temporaryDirectory.appending(path: "migration-denied-\(UUID())")
    await #expect(throws: (any Error).self) { try await V1MigrationAdapter().migrate(source: DeniedSource(), destinationRoot: destination, migrationID: UUID(), availableCapacityBytes: 10_000_000) }
    #expect(((try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []).allSatisfy { !$0.hasSuffix(".ready") })
    try? FileManager.default.removeItem(at: destination)
}
