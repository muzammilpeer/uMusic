import CryptoKit
import Foundation
import Testing
import UMusicDomain
import UMusicOffline

private actor OfflineAuthenticationStub: AuthenticationManaging {
    nonisolated let snapshots = AsyncStream<AuthenticationState> { $0.finish() }
    func restore() async {}
    func connect(serverURL: String, username: String, password: String, keepSignedIn: Bool, allowsInsecureLocalhost: Bool) async {}
    func validAccessToken() async throws -> String { "access" }
    func currentServer() async throws -> ServerConfiguration { .init(baseURL: URL(string: "https://music.example")!) }
    func logout(localData: LogoutLocalDataDisposition) async {}
}

private actor OfflineTicketStub: PlaybackTicketAPI {
    var content: [UUID: Data] = [:]
    var expiresAt = Date.distantFuture
    func set(_ data: Data, for id: UUID) { content[id] = data }
    func expire() { expiresAt = .distantPast }
    func tickets(server: ServerConfiguration, accessToken: String, trackIDs: [UUID]) async throws -> [PlaybackTicket] {
        trackIDs.compactMap { id in
            guard let data = content[id] else { return nil }
            let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return PlaybackTicket(trackID: id, url: URL(string: "https://music.example/\(id)")!, expiresAt: expiresAt, checksum: checksum, bytes: Int64(data.count), supportsRanges: true)
        }
    }
}

private final class DownloadTransportStub: MediaDownloadTransport, @unchecked Sendable {
    enum Mode { case valid, corrupt, partial, offline, diskFull }
    nonisolated let recoveredDownloads: AsyncStream<DownloadedMedia>
    private let continuation: AsyncStream<DownloadedMedia>.Continuation
    private let lock = NSLock()
    private var contents: [UUID: Data] = [:]
    private var callCount = 0
    var mode: Mode = .valid
    private(set) var restoreCount = 0

    init() { let stream = AsyncStream<DownloadedMedia>.makeStream(); recoveredDownloads = stream.stream; continuation = stream.continuation }
    func set(_ data: Data, for id: UUID) { lock.withLock { contents[id] = data } }
    func calls() -> Int { lock.withLock { callCount } }
    func download(_ request: MediaDownloadRequest, allowsCellular: Bool) async throws -> DownloadedMedia {
        lock.withLock { callCount += 1 }
        if mode == .offline { throw URLError(.notConnectedToInternet) }
        if mode == .diskFull { throw CocoaError(.fileWriteOutOfSpace) }
        var data = lock.withLock { contents[request.track.id] ?? Data() }
        if mode == .corrupt { data.append(0xff) }
        if mode == .partial, !data.isEmpty { data.removeLast() }
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try data.write(to: url)
        return DownloadedMedia(request: request, temporaryURL: url)
    }
    func restoreTasks() async { lock.withLock { restoreCount += 1 } }
    func restores() -> Int { lock.withLock { restoreCount } }
    func yieldRecovered(_ value: DownloadedMedia) { continuation.yield(value) }
}

private func offlineTrack(_ title: String = "Offline") -> TrackSummary { .init(id: UUID(), title: title, artist: "Artist", durationSeconds: 60) }
private func temporaryOfflineRoot() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory) }

private func makeOfflineCoordinator(root: URL, quota: Int64 = 500_000_000, mode: DownloadTransportStub.Mode = .valid, tracks: [(TrackSummary, Data)]) async -> (DownloadCoordinator, DownloadTransportStub, OfflineTicketStub) {
    let transport = DownloadTransportStub(); transport.mode = mode
    let tickets = OfflineTicketStub()
    for (track, data) in tracks { transport.set(data, for: track.id); await tickets.set(data, for: track.id) }
    return (DownloadCoordinator(root: root, transport: transport, tickets: tickets, authentication: OfflineAuthenticationStub(), initialQuotaBytes: quota), transport, tickets)
}

@Test("Verified downloads commit atomically and survive coordinator relaunch")
func offlineDownloadAndRelaunch() async throws {
    let root = temporaryOfflineRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let track = offlineTrack(); let data = Data(repeating: 0x5a, count: 128)
    let (coordinator, _, tickets) = await makeOfflineCoordinator(root: root, tracks: [(track, data)])
    try await coordinator.download(track, retention: .pinned)
    let cached = await coordinator.cachedFile(for: track.id)
    #expect(cached != nil)
    #expect(try Data(contentsOf: cached!) == data)
    let transport2 = DownloadTransportStub()
    let restored = DownloadCoordinator(root: root, transport: transport2, tickets: tickets, authentication: OfflineAuthenticationStub())
    #expect(await restored.cachedFile(for: track.id) != nil)
    #expect(await restored.storageSnapshot().entries.first?.retention == .pinned)
}

@Test("Duplicate concurrent requests share one transfer")
func duplicateOfflineRequestsDeduplicate() async throws {
    let root = temporaryOfflineRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let track = offlineTrack(); let data = Data(repeating: 1, count: 64)
    let (coordinator, transport, _) = await makeOfflineCoordinator(root: root, tracks: [(track, data)])
    async let first: Void = coordinator.download(track, retention: .rolling)
    async let second: Void = coordinator.download(track, retention: .pinned)
    _ = try await (first, second)
    #expect(transport.calls() == 1)
}

@Test("Checksum and partial-size failures never enter the cache index")
func corruptAndPartialDownloadsFail() async {
    for mode in [DownloadTransportStub.Mode.corrupt, .partial] {
        let root = temporaryOfflineRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let track = offlineTrack(); let data = Data(repeating: 2, count: 64)
        let (coordinator, _, _) = await makeOfflineCoordinator(root: root, mode: mode, tracks: [(track, data)])
        await #expect(throws: (any Error).self) { try await coordinator.download(track, retention: .rolling) }
        #expect(await coordinator.cachedFile(for: track.id) == nil)
    }
}

@Test("Expired tickets, airplane mode, and disk-full errors remain non-destructive")
func offlineFailureModes() async {
    let track = offlineTrack(); let data = Data(repeating: 3, count: 16)
    for mode in [DownloadTransportStub.Mode.offline, .diskFull] {
        let root = temporaryOfflineRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let (coordinator, _, _) = await makeOfflineCoordinator(root: root, mode: mode, tracks: [(track, data)])
        await #expect(throws: (any Error).self) { try await coordinator.download(track, retention: .rolling) }
        #expect(await coordinator.storageSnapshot().usedBytes == 0)
    }
    let root = temporaryOfflineRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let (coordinator, transport, tickets) = await makeOfflineCoordinator(root: root, tracks: [(track, data)])
    await tickets.expire()
    await #expect(throws: OfflineDownloadError.self) { try await coordinator.download(track, retention: .rolling) }
    #expect(transport.calls() == 0)
}

@Test("Hard quota evicts rolling LRU but protects pinned and playing media")
func hardQuotaProtection() async throws {
    let root = temporaryOfflineRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let first = offlineTrack("First"), second = offlineTrack("Second")
    let (coordinator, _, _) = await makeOfflineCoordinator(root: root, quota: 10, tracks: [(first, Data(repeating: 1, count: 6)), (second, Data(repeating: 2, count: 6))])
    try await coordinator.download(first, retention: .rolling)
    try await coordinator.download(second, retention: .rolling)
    #expect(await coordinator.cachedFile(for: first.id) == nil)
    #expect(await coordinator.cachedFile(for: second.id) != nil)

    try await coordinator.removeDownload(trackID: second.id)
    try await coordinator.download(first, retention: .pinned)
    await #expect(throws: OfflineDownloadError.self) { try await coordinator.download(second, retention: .rolling) }
    await #expect(throws: OfflineDownloadError.self) { try await coordinator.setQuota(bytes: 5) }
    #expect(await coordinator.storageSnapshot().quotaBytes == 10)
}

@Test("Currently playing rolling media cannot be evicted or deleted")
func playingMediaIsProtected() async throws {
    let root = temporaryOfflineRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let first = offlineTrack("Playing"), second = offlineTrack("Other")
    let (coordinator, _, _) = await makeOfflineCoordinator(root: root, quota: 10, tracks: [(first, Data(repeating: 1, count: 6)), (second, Data(repeating: 2, count: 6))])
    try await coordinator.download(first, retention: .rolling)
    await coordinator.setCurrentlyPlaying(trackID: first.id)
    await #expect(throws: OfflineDownloadError.self) { try await coordinator.download(second, retention: .rolling) }
    await #expect(throws: OfflineDownloadError.self) { try await coordinator.removeDownload(trackID: first.id) }
    #expect(await coordinator.cachedFile(for: first.id) != nil)
}

@Test("Remove all downloads clears every device file including the playing track")
func removeAllDownloadsIncludesPlayback() async throws {
    let root = temporaryOfflineRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let playing = offlineTrack("Playing"), other = offlineTrack("Other")
    let (coordinator, _, _) = await makeOfflineCoordinator(
        root: root,
        tracks: [(playing, Data(repeating: 1, count: 6)), (other, Data(repeating: 2, count: 7))]
    )
    try await coordinator.download(playing, retention: .pinned)
    try await coordinator.download(other, retention: .rolling)
    await coordinator.setCurrentlyPlaying(trackID: playing.id)

    try await coordinator.removeAllDownloads()

    let cleared = await coordinator.storageSnapshot()
    #expect(cleared.entries.isEmpty)
    #expect(cleared.usedBytes == 0)
    #expect(await coordinator.cachedFile(for: playing.id) == nil)
    #expect(await coordinator.cachedFile(for: other.id) == nil)
}

@Test("Reconciliation removes orphan files without touching catalog state")
func offlineReconciliation() async throws {
    let root = temporaryOfflineRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let media = root.appending(path: "media", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
    let orphan = media.appending(path: "orphan.mp3"); try Data([1]).write(to: orphan)
    let (coordinator, _, _) = await makeOfflineCoordinator(root: root, tracks: [])
    await coordinator.reconcile()
    #expect(!FileManager.default.fileExists(atPath: orphan.path))
}

@Test("Restored background completion is verified and committed")
func restoredBackgroundCompletion() async throws {
    let root = temporaryOfflineRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let track = offlineTrack("Recovered"), data = Data(repeating: 7, count: 24)
    let (coordinator, transport, tickets) = await makeOfflineCoordinator(root: root, tracks: [(track, data)])
    for _ in 0..<20 where transport.restores() == 0 { await Task.yield() }
    #expect(transport.restores() == 1)
    let ticket = try #require(await tickets.tickets(server: .init(baseURL: URL(string: "https://music.example")!), accessToken: "a", trackIDs: [track.id]).first)
    let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try data.write(to: file)
    transport.yieldRecovered(DownloadedMedia(request: .init(track: track, ticket: ticket), temporaryURL: file))
    var cached: URL?
    for _ in 0..<40 { cached = await coordinator.cachedFile(for: track.id); if cached != nil { break }; await Task.yield() }
    #expect(cached != nil)
}

@Test("Cellular policy is explicit and persisted")
func cellularPolicyPersists() async {
    let root = temporaryOfflineRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let (coordinator, transport, tickets) = await makeOfflineCoordinator(root: root, tracks: [])
    #expect(await coordinator.storageSnapshot().allowsCellular == false)
    await coordinator.setAllowsCellular(true)
    let restored = DownloadCoordinator(root: root, transport: transport, tickets: tickets, authentication: OfflineAuthenticationStub())
    #expect(await restored.storageSnapshot().allowsCellular == true)
}
