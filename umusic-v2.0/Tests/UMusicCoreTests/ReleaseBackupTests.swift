import Foundation
import Testing
import UMusicData

@Test("Release backup round-trips fixed stores with hashes and refuses overwrite")
func releaseBackupRoundTrip() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let stores = root.appending(path: "stores")
    let archive = root.appending(path: "backup.ready")
    let restored = root.appending(path: "restored")
    try FileManager.default.createDirectory(at: stores.appending(path: "Offline"), withIntermediateDirectories: true)
    try Data("catalog".utf8).write(to: stores.appending(path: "Catalog.sqlite"))
    try Data("queue".utf8).write(to: stores.appending(path: "Queue-v1.json"))
    try Data("offline".utf8).write(to: stores.appending(path: "Offline/index-v1.json"))

    let coordinator = ReleaseBackupCoordinator()
    let created = try await coordinator.createSnapshot(from: stores, at: archive)
    #expect(created.files.count == 3)
    let result = try await coordinator.restoreSnapshot(from: archive, toEmptyStoreRoot: restored)
    #expect(result == created)
    #expect(try Data(contentsOf: restored.appending(path: "Queue-v1.json")) == Data("queue".utf8))
    await #expect(throws: ReleaseBackupError.destinationNotEmpty) {
        try await coordinator.restoreSnapshot(from: archive, toEmptyStoreRoot: restored)
    }
}

@Test("Release backup rejects corruption without writing a restore")
func releaseBackupCorruption() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let stores = root.appending(path: "stores")
    let archive = root.appending(path: "backup.ready")
    let restored = root.appending(path: "restored")
    try FileManager.default.createDirectory(at: stores, withIntermediateDirectories: true)
    try Data("queue".utf8).write(to: stores.appending(path: "Queue-v1.json"))
    let coordinator = ReleaseBackupCoordinator()
    _ = try await coordinator.createSnapshot(from: stores, at: archive)
    try Data("tampered".utf8).write(to: archive.appending(path: "Queue-v1.json"))

    await #expect(throws: ReleaseBackupError.invalidArchive) {
        try await coordinator.restoreSnapshot(from: archive, toEmptyStoreRoot: restored)
    }
    #expect(!FileManager.default.fileExists(atPath: restored.appending(path: "Queue-v1.json").path))
}
