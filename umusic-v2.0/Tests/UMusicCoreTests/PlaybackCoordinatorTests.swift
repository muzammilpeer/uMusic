import Foundation
import Testing
import UMusicCore
import UMusicData
import UMusicDomain

@MainActor
private final class PlaybackEngineSpy: MediaPlaybackEngine, @unchecked Sendable {
    nonisolated let events: AsyncStream<PlaybackEngineEvent>
    private let continuation: AsyncStream<PlaybackEngineEvent>.Continuation
    var preparedURLs: [URL] = []
    var playCount = 0
    var seekValues: [Double] = []
    var handler: (@Sendable (PlaybackCommand) -> Void)?

    init() { let stream = AsyncStream<PlaybackEngineEvent>.makeStream(); events = stream.stream; continuation = stream.continuation }
    func prepare(url: URL) async throws { preparedURLs.append(url); continuation.yield(.ready(duration: 120)) }
    func play() async { playCount += 1; continuation.yield(.playing) }
    func pause() async { continuation.yield(.paused) }
    func seek(to seconds: Double) async { seekValues.append(seconds); continuation.yield(.time(position: seconds, duration: 120)) }
    func configure(track: TrackSummary?, commandHandler: @escaping @Sendable (PlaybackCommand) -> Void) async { handler = commandHandler }
    func send(_ event: PlaybackEngineEvent) { continuation.yield(event) }
    func command(_ value: PlaybackCommand) { handler?(value) }
}

@MainActor @Test("Restoration publishes immediately, seeks, and never autoplays")
func playbackRestorationIsPaused() async {
    let items = playbackTracks.map { QueueItem(track: $0, origin: .manual) }
    let restored = DurableQueueSnapshot(items: items, currentIndex: 1, positionSeconds: 37, sourceIdentity: .remote)
    let engine = PlaybackEngineSpy(); let api = TicketAPIStub()
    let coordinator = PlaybackCoordinator(engine: engine, tickets: api, cache: CacheStub(), authentication: PlaybackAuthenticationStub(), restoredSnapshot: restored)
    var values = coordinator.snapshots.makeAsyncIterator()
    let immediate = await values.next()
    #expect(immediate?.phase == .paused)
    #expect(immediate?.track?.id == playbackTracks[1].id)
    #expect(immediate?.positionSeconds == 37)
    for _ in 0..<20 where engine.seekValues.isEmpty { await Task.yield() }
    #expect(engine.seekValues.last == 37)
    #expect(engine.playCount == 0)
    #expect(await api.count() == 1)
}

@MainActor @Test("A play request during restored preparation is honored only after ready")
func playDuringRestorationPreparation() async {
    let restored = DurableQueueSnapshot(items: [QueueItem(track: playbackTracks[0], origin: .manual)], currentIndex: 0, positionSeconds: 12, sourceIdentity: .remote)
    let engine = PlaybackEngineSpy()
    let coordinator = PlaybackCoordinator(engine: engine, tickets: TicketAPIStub(), cache: CacheStub(), authentication: PlaybackAuthenticationStub(), restoredSnapshot: restored)
    await coordinator.play()
    for _ in 0..<20 where engine.playCount == 0 { await Task.yield() }
    #expect(engine.playCount == 1)
    #expect(engine.seekValues.first == 12)
}

@MainActor @Test("Manual next and later items remain ahead of automatic refill")
func manualQueuePriority() async {
    let engine = PlaybackEngineSpy()
    let coordinator = PlaybackCoordinator(engine: engine, tickets: TicketAPIStub(), cache: CacheStub(), authentication: PlaybackAuthenticationStub())
    var values = coordinator.snapshots.makeAsyncIterator(); _ = await values.next()
    await coordinator.setQueue([playbackTracks[0]], startingAt: 0)
    for _ in 0..<3 { _ = await values.next() }
    let automatic = TrackSummary(id: UUID(), title: "Automatic", artist: "Model")
    let later = TrackSummary(id: UUID(), title: "Later", artist: "Person")
    let next = TrackSummary(id: UUID(), title: "Next", artist: "Person")
    await coordinator.enqueue(automatic, placement: .later, origin: .automatic)
    await coordinator.enqueue(later, placement: .later, origin: .manual)
    await coordinator.enqueue(next, placement: .next, origin: .manual)
    var latest: PlaybackSnapshot?
    for _ in 0..<3 { latest = await values.next() }
    #expect(latest?.queue.map(\.track.title) == ["One", "Next", "Later", "Automatic"])
    #expect(latest?.queue.map(\.origin) == [.manual, .manual, .manual, .automatic])
}

@MainActor @Test("Duplicate tracks retain distinct durable queue identities")
func duplicateQueueItemsRemainDistinct() async {
    let coordinator = PlaybackCoordinator(engine: PlaybackEngineSpy(), tickets: TicketAPIStub(), cache: CacheStub(), authentication: PlaybackAuthenticationStub())
    var values = coordinator.snapshots.makeAsyncIterator(); _ = await values.next()
    await coordinator.setQueue([playbackTracks[0], playbackTracks[0]], startingAt: 0)
    let preparing = await values.next()
    #expect(preparing?.queue.count == 2)
    #expect(Set(preparing?.queue.map(\.id) ?? []).count == 2)
}

@MainActor @Test("Empty authoritative library clears restored playback queue")
func emptyLibraryClearsRestoredQueue() async {
    let store = MemoryQueueSnapshotStore()
    let restored = DurableQueueSnapshot(
        items: playbackTracks.map { QueueItem(track: $0, origin: .automatic) },
        currentIndex: 0,
        positionSeconds: 30,
        sourceIdentity: .cached
    )
    let coordinator = PlaybackCoordinator(
        engine: PlaybackEngineSpy(),
        tickets: TicketAPIStub(),
        cache: CacheStub(),
        authentication: PlaybackAuthenticationStub(),
        snapshotStore: store,
        restoredSnapshot: restored
    )
    await coordinator.reconcileQueue(availableTracks: [])

    let cleared = await coordinator.currentSnapshot()
    #expect(cleared == .idle)
    #expect(await store.value() == nil)
}

@MainActor @Test("Position ticks checkpoint no more often than the fifteen-second boundary")
func checkpointWriteBudget() async {
    let engine = PlaybackEngineSpy(); let store = MemoryQueueSnapshotStore()
    let coordinator = PlaybackCoordinator(engine: engine, tickets: TicketAPIStub(), cache: CacheStub(), authentication: PlaybackAuthenticationStub(), snapshotStore: store)
    await coordinator.setQueue([playbackTracks[0]], startingAt: 0)
    for _ in 0..<20 { await Task.yield() }
    let baseline = await store.writes()
    for second in 1...14 { engine.send(.time(position: Double(second), duration: 120)) }
    for _ in 0..<20 { await Task.yield() }
    #expect(await store.writes() == baseline)
    engine.send(.time(position: 15, duration: 120))
    for _ in 0..<20 {
        if await store.writes() != baseline { break }
        await Task.yield()
    }
    #expect(await store.writes() == baseline + 1)
}

@Test("Queue snapshot file rejects corrupt and structurally invalid state")
func corruptQueueSnapshotIsIgnored() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("not-json".utf8).write(to: url)
    #expect(FileQueueSnapshotStore.load(from: url) == nil)
    let invalid = DurableQueueSnapshot(items: [], currentIndex: 4, positionSeconds: 0, sourceIdentity: .unknown)
    try JSONEncoder().encode(invalid).write(to: url)
    #expect(FileQueueSnapshotStore.load(from: url) == nil)
}

@MainActor @Test("Queue exhaustion remains on the final track in a paused state")
func queueExhaustionPauses() async {
    let engine = PlaybackEngineSpy()
    let coordinator = PlaybackCoordinator(engine: engine, tickets: TicketAPIStub(), cache: CacheStub(), authentication: PlaybackAuthenticationStub())
    var values = coordinator.snapshots.makeAsyncIterator(); _ = await values.next()
    await coordinator.setQueue([playbackTracks[0]], startingAt: 0)
    _ = await values.next(); _ = await values.next(); _ = await values.next()
    engine.send(.ended)
    let exhausted = await values.next()
    #expect(exhausted?.phase == .paused)
    #expect(exhausted?.track?.id == playbackTracks[0].id)
    #expect(exhausted?.canGoNext == false)
}

@MainActor @Test("Removing and moving duplicate queue items uses item identity")
func queueMutationUsesItemIdentity() async {
    let coordinator = PlaybackCoordinator(engine: PlaybackEngineSpy(), tickets: TicketAPIStub(), cache: CacheStub(), authentication: PlaybackAuthenticationStub())
    var values = coordinator.snapshots.makeAsyncIterator(); _ = await values.next()
    await coordinator.setQueue([playbackTracks[0], playbackTracks[0], playbackTracks[1]], startingAt: 0)
    let initial = await values.next()!
    let duplicateID = initial.queue[1].id
    await coordinator.removeQueueItem(id: duplicateID)
    var removed = await values.next()!
    for _ in 0..<4 where removed.queue.count != 2 { removed = await values.next()! }
    #expect(removed.queue.count == 2)
    #expect(!removed.queue.contains(where: { $0.id == duplicateID }))
    let lastID = removed.queue[1].id
    await coordinator.moveQueueItems(fromOffsets: IndexSet(integer: 1), toOffset: 0)
    var moved = await values.next()!
    for _ in 0..<4 where moved.queue.first?.id != lastID { moved = await values.next()! }
    #expect(moved.queue.first?.id == lastID)
    #expect(moved.currentQueueItemID == initial.currentQueueItemID)
}

private actor PlaybackAuthenticationStub: AuthenticationManaging {
    nonisolated let snapshots = AsyncStream<AuthenticationState> { $0.finish() }
    let server = ServerConfiguration(baseURL: URL(string: "https://music.example")!)
    func restore() async {}
    func connect(serverURL: String, username: String, password: String, keepSignedIn: Bool, allowsInsecureLocalhost: Bool) async {}
    func validAccessToken() async throws -> String { "access" }
    func currentServer() async throws -> ServerConfiguration { server }
    func logout(localData: LogoutLocalDataDisposition) async {}
}

private actor TicketAPIStub: PlaybackTicketAPI {
    var expiry = Date.distantFuture
    var calls = 0
    func tickets(server: ServerConfiguration, accessToken: String, trackIDs: [UUID]) async throws -> [PlaybackTicket] {
        calls += 1
        return trackIDs.map { PlaybackTicket(trackID: $0, url: URL(string: "https://music.example/stream/\($0)")!, expiresAt: expiry, checksum: String(repeating: "a", count: 64), bytes: 10, supportsRanges: true) }
    }
    func count() -> Int { calls }
    func setExpiry(_ value: Date) { expiry = value }
}

private actor CacheStub: CachedMediaLocating {
    var url: URL?
    init(url: URL? = nil) { self.url = url }
    func cachedFile(for trackID: UUID) async -> URL? { url }
    func setCurrentlyPlaying(trackID: UUID?) async {}
}

private actor AutomaticQueueStub: AutomaticQueueProviding {
    let tracks: [TrackSummary]
    var requests: [(Set<UUID>, Int)] = []
    init(tracks: [TrackSummary]) { self.tracks = tracks }
    func automaticTracks(excluding trackIDs: Set<UUID>, count: Int, at date: Date) async -> [TrackSummary] {
        requests.append((trackIDs, count)); return Array(tracks.filter { !trackIDs.contains($0.id) }.prefix(count))
    }
    func requestCount() -> Int { requests.count }
}

private let playbackTracks = [
    TrackSummary(id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!, title: "One", artist: "Artist", durationSeconds: 120),
    TrackSummary(id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!, title: "Two", artist: "Artist", durationSeconds: 90),
]

@MainActor @Test("Playback transitions from preparation to playing and advances on completion")
func playbackTransitionsAndAdvances() async throws {
    let engine = PlaybackEngineSpy(); let api = TicketAPIStub()
    let coordinator = PlaybackCoordinator(engine: engine, tickets: api, cache: CacheStub(), authentication: PlaybackAuthenticationStub())
    var values = coordinator.snapshots.makeAsyncIterator()
    #expect(await values.next()?.phase == .idle)
    await coordinator.setQueue(playbackTracks, startingAt: 0)
    #expect(await values.next()?.phase == .preparing)
    #expect(await values.next()?.phase == .paused)
    #expect(await values.next()?.phase == .playing)
    engine.send(.ended)
    #expect(await values.next()?.track?.id == playbackTracks[1].id)
}

@MainActor @Test("Automatic refill starts at eight remaining and stays behind manual intent")
func automaticQueueRefillThreshold() async {
    let initial = (0..<10).map { TrackSummary(id: UUID(), title: "Manual \($0)", artist: "Person") }
    let refill = (0..<25).map { TrackSummary(id: UUID(), title: "Automatic \($0)", artist: "Model") }
    let provider = AutomaticQueueStub(tracks: refill)
    let coordinator = PlaybackCoordinator(engine: PlaybackEngineSpy(), tickets: TicketAPIStub(), cache: CacheStub(), authentication: PlaybackAuthenticationStub(), automaticQueueProvider: provider)
    var values = coordinator.snapshots.makeAsyncIterator(); _ = await values.next()
    await coordinator.setQueue(initial, startingAt: 0)
    await coordinator.next()
    #expect(await provider.requestCount() == 1)
    var latest: PlaybackSnapshot?
    for _ in 0..<8 {
        guard let snapshot = await values.next() else { break }
        latest = snapshot; if snapshot.queue.count >= 26 { break }
    }
    let queue = latest?.queue ?? []
    #expect(queue.prefix(10).allSatisfy { $0.origin == .manual })
    #expect(queue.dropFirst(10).allSatisfy { $0.origin == .automatic })
}

@MainActor @Test("Cached media is preferred without requesting a remote ticket")
func cachedPlaybackWins() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try Data("audio".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let engine = PlaybackEngineSpy(); let api = TicketAPIStub()
    let coordinator = PlaybackCoordinator(engine: engine, tickets: api, cache: CacheStub(url: file), authentication: PlaybackAuthenticationStub())
    await coordinator.setQueue(playbackTracks, startingAt: 0)
    #expect(engine.preparedURLs.last == file)
    #expect(await api.count() == 0)
}

@MainActor @Test("Expired tickets fail safely instead of reaching the player")
func expiredTicketFails() async {
    let engine = PlaybackEngineSpy(); let api = TicketAPIStub(); await api.setExpiry(.distantPast)
    let coordinator = PlaybackCoordinator(engine: engine, tickets: api, cache: CacheStub(), authentication: PlaybackAuthenticationStub())
    var values = coordinator.snapshots.makeAsyncIterator(); _ = await values.next()
    await coordinator.setQueue(playbackTracks, startingAt: 0)
    _ = await values.next()
    let failed = await values.next()
    #expect(failed?.phase == .failed)
    #expect(engine.preparedURLs.isEmpty)
}

@MainActor @Test("Route loss pauses and remote commands use the same coordinator")
func routeLossAndRemoteCommand() async {
    let engine = PlaybackEngineSpy()
    let coordinator = PlaybackCoordinator(engine: engine, tickets: TicketAPIStub(), cache: CacheStub(), authentication: PlaybackAuthenticationStub())
    var values = coordinator.snapshots.makeAsyncIterator(); _ = await values.next()
    await coordinator.setQueue(playbackTracks, startingAt: 0)
    _ = await values.next(); _ = await values.next(); _ = await values.next()
    engine.send(.routeOutputLost)
    #expect(await values.next()?.phase == .paused)
    engine.command(.next)
    var advanced = false
    for _ in 0..<4 {
        if await values.next()?.track?.id == playbackTracks[1].id { advanced = true; break }
    }
    #expect(advanced)
}
