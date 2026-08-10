import Foundation
import UMusicDomain

public actor FileQueueSnapshotStore: QueueSnapshotStoring {
    public let url: URL
    private let encoder = JSONEncoder()

    public init(url: URL) { self.url = url }

    public static func load(from url: URL) -> DurableQueueSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(DurableQueueSnapshot.self, from: data),
              snapshot.schemaVersion == 1,
              snapshot.items.indices.contains(snapshot.currentIndex),
              snapshot.positionSeconds.isFinite else { return nil }
        return snapshot
    }

    public func save(_ snapshot: DurableQueueSnapshot) async throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    public func remove() async throws { try? FileManager.default.removeItem(at: url) }
}

public actor MemoryQueueSnapshotStore: QueueSnapshotStoring {
    public private(set) var snapshot: DurableQueueSnapshot?
    public private(set) var saveCount = 0
    public init(snapshot: DurableQueueSnapshot? = nil) { self.snapshot = snapshot }
    public func save(_ snapshot: DurableQueueSnapshot) async throws { self.snapshot = snapshot; saveCount += 1 }
    public func remove() async throws { snapshot = nil }
    public func value() -> DurableQueueSnapshot? { snapshot }
    public func writes() -> Int { saveCount }
}
