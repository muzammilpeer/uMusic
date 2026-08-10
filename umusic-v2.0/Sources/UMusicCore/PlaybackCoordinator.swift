import Foundation
import UMusicData
import UMusicDomain
import UMusicSupport

public actor PlaybackCoordinator: PlaybackControlling {
    public nonisolated let snapshots: AsyncStream<PlaybackSnapshot>
    private let continuation: AsyncStream<PlaybackSnapshot>.Continuation
    private let engine: any MediaPlaybackEngine
    private let tickets: any PlaybackTicketAPI
    private let cache: any CachedMediaLocating
    private let authentication: any AuthenticationManaging
    private let snapshotStore: any QueueSnapshotStoring
    private let logger: any RedactedLogging
    private let learning: (any PlaybackLearningRecording)?
    private let automaticQueueProvider: (any AutomaticQueueProviding)?
    private var queue: [QueueItem] = []
    private var index = 0
    private var phase: PlaybackPhase = .idle
    private var position = 0.0
    private var duration: Double?
    private var wantsPlayback = false
    private var resumeAfterInterruption = false
    private var preparationID = UUID()
    private var failureMessage: String?
    private var sourceIdentity: PlaybackSourceIdentity = .unknown
    private var pendingSeek: Double?
    private var lastCheckpointPosition = 0.0
    private var isPrepared = false
    private var learningTrackID: UUID?
    private var isRefilling = false

    public init(engine: any MediaPlaybackEngine, tickets: any PlaybackTicketAPI, cache: any CachedMediaLocating, authentication: any AuthenticationManaging, snapshotStore: any QueueSnapshotStoring = MemoryQueueSnapshotStore(), restoredSnapshot: DurableQueueSnapshot? = nil, logger: any RedactedLogging = RedactedLogger(category: "playback"), learning: (any PlaybackLearningRecording)? = nil, automaticQueueProvider: (any AutomaticQueueProviding)? = nil) {
        self.engine = engine; self.tickets = tickets; self.cache = cache
        self.authentication = authentication; self.snapshotStore = snapshotStore; self.logger = logger; self.learning = learning; self.automaticQueueProvider = automaticQueueProvider
        if let restoredSnapshot, restoredSnapshot.items.indices.contains(restoredSnapshot.currentIndex) {
            queue = restoredSnapshot.items; index = restoredSnapshot.currentIndex
            position = restoredSnapshot.positionSeconds; pendingSeek = position
            lastCheckpointPosition = position; sourceIdentity = restoredSnapshot.sourceIdentity
            phase = .paused
        }
        let stream = AsyncStream<PlaybackSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(4))
        snapshots = stream.stream; continuation = stream.continuation
        let initialItem = queue[safe: index]
        let initialCanGoPrevious = index > 0 ? true : position > 0
        continuation.yield(.init(phase: phase, track: initialItem?.track, positionSeconds: position, queueCount: max(queue.count - index - 1, 0), canGoNext: index + 1 < queue.count, canGoPrevious: initialCanGoPrevious, failureMessage: failureMessage, queue: queue, currentQueueItemID: initialItem?.id))
        Task { await self.consumeEngineEvents() }
        Task {
            await engine.configure(track: nil) { command in Task { await self.handle(command) } }
        }
        if restoredSnapshot != nil { Task { await self.prepareCurrent(startingAt: self.position) } }
    }

    deinit { continuation.finish() }

    public func setQueue(_ tracks: [TrackSummary], startingAt index: Int) async {
        await replaceQueue(tracks, startingAt: index, origin: .manual)
    }

    public func setAutomaticQueue(_ tracks: [TrackSummary], startingAt index: Int) async {
        await replaceQueue(tracks, startingAt: index, origin: .automatic)
    }

    private func replaceQueue(_ tracks: [TrackSummary], startingAt index: Int, origin: QueueItemOrigin) async {
        guard tracks.indices.contains(index) else { return }
        if learningTrackID != nil { await learning?.record(.ended(positionSeconds: position, durationSeconds: duration, reason: .replaced)); learningTrackID = nil }
        queue = tracks.map { QueueItem(track: $0, origin: origin) }; self.index = index; wantsPlayback = true
        await prepareCurrent()
        await persist()
    }

    public func enqueue(trackID: UUID, placement: QueuePlacement) async {
        guard let track = queue.first(where: { $0.track.id == trackID })?.track else { return }
        await enqueue(track, placement: placement, origin: .manual)
    }

    public func enqueue(_ track: TrackSummary, placement: QueuePlacement, origin: QueueItemOrigin) async {
        let item = QueueItem(track: track, origin: origin)
        if queue.isEmpty {
            queue = [item]; index = 0; phase = .paused; wantsPlayback = placement == .now
            if placement == .now { await prepareCurrent() } else { emit() }
            await persist(); return
        }
        switch placement {
        case .now:
            queue.insert(item, at: min(index + 1, queue.count)); index += 1
            wantsPlayback = true; await prepareCurrent()
        case .next:
            let insertion = origin == .manual ? min(index + 1, queue.count) : queue.count
            queue.insert(item, at: insertion)
        case .later:
            let insertion = origin == .manual ? firstAutomaticUpcomingIndex() : queue.count
            queue.insert(item, at: insertion)
        }
        normalizeUpcomingPriority(); emit(); await persist()
    }

    public func removeQueueItem(id: UUID) async {
        guard let removal = queue.firstIndex(where: { $0.id == id }) else { return }
        if removal == index {
            queue.remove(at: removal)
            if queue.isEmpty { index = 0; phase = .idle; position = 0; wantsPlayback = false; await cache.setCurrentlyPlaying(trackID: nil); await engine.pause(); await engine.configure(track: nil) { _ in } }
            else { index = min(removal, queue.count - 1); await prepareCurrent() }
        } else {
            queue.remove(at: removal); if removal < index { index -= 1 }
        }
        emit(); await persist()
    }

    public func moveQueueItems(fromOffsets: IndexSet, toOffset: Int) async {
        let movable = fromOffsets.filter { queue.indices.contains($0) && $0 != index }
        guard !movable.isEmpty else { return }
        let currentID = queue[index].id
        let moved = movable.map { queue[$0] }
        for offset in movable.sorted(by: >) { queue.remove(at: offset) }
        let removedBefore = movable.filter { $0 < toOffset }.count
        let destination = min(max(toOffset - removedBefore, 0), queue.count)
        queue.insert(contentsOf: moved, at: destination)
        index = queue.firstIndex(where: { $0.id == currentID }) ?? 0
        normalizeUpcomingPriority(); emit(); await persist()
    }

    public func checkpoint() async { await learning?.record(.checkpoint(positionSeconds: position, durationSeconds: duration)); await learning?.flush(); await persist() }

    public func play() async {
        wantsPlayback = true
        if (phase == .paused || phase == .interrupted) && isPrepared { await engine.play() }
        else if phase == .paused && !isPrepared, !queue.isEmpty { await prepareCurrent(startingAt: position) }
        else if phase == .failed, !queue.isEmpty { await prepareCurrent() }
    }

    public func pause() async { wantsPlayback = false; await engine.pause(); await persist() }
    public func next() async {
        if index + 1 >= queue.count { await maybeRefill() }
        guard index + 1 < queue.count else { return }
        if learningTrackID != nil { await learning?.record(.ended(positionSeconds: position, durationSeconds: duration, reason: .skipped)); learningTrackID = nil }
        let continuePlaying = phase == .playing || wantsPlayback
        index += 1; wantsPlayback = continuePlaying; await prepareCurrent(); await maybeRefill(); await persist()
    }
    public func previous() async {
        if position > 5 { await seek(to: 0); return }
        guard index > 0 else { await seek(to: 0); return }
        if learningTrackID != nil { await learning?.record(.ended(positionSeconds: position, durationSeconds: duration, reason: .skipped)); learningTrackID = nil }
        let continuePlaying = phase == .playing || wantsPlayback
        index -= 1; wantsPlayback = continuePlaying; await prepareCurrent(); await persist()
    }
    public func seek(to seconds: Double) async {
        let previousPosition = position
        position = min(max(seconds, 0), duration ?? .greatestFiniteMagnitude)
        await learning?.record(.seeked(fromSeconds: previousPosition, toSeconds: position))
        await engine.seek(to: position); emit(); await persist()
    }
    public func skip(by seconds: Double) async { await seek(to: position + seconds) }

    private func prepareCurrent(startingAt startPosition: Double = 0) async {
        let interval = PerformanceSignposts.begin("PlaybackPrepare"); defer { PerformanceSignposts.end(interval) }
        guard queue.indices.contains(index) else { return }
        let operation = UUID(); preparationID = operation
        isPrepared = false
        phase = .preparing; position = max(startPosition, 0); pendingSeek = position > 0 ? position : nil; failureMessage = nil; emit()
        let track = queue[index].track
        await cache.setCurrentlyPlaying(trackID: track.id)
        await engine.configure(track: track) { command in Task { await self.handle(command) } }
        do {
            let (url, identity) = try await sourceURL(for: track.id)
            guard operation == preparationID else { return }
            sourceIdentity = identity
            try await engine.prepare(url: url)
        } catch is CancellationError {
        } catch {
            guard operation == preparationID else { return }
            phase = .failed; wantsPlayback = false; failureMessage = "This track is currently unavailable."
            logger.error("playback_prepare_failed", fields: [LogField("track_id", track.id.uuidString, privacy: .sensitive)])
            emit()
        }
    }

    private func sourceURL(for trackID: UUID) async throws -> (URL, PlaybackSourceIdentity) {
        if let local = await cache.cachedFile(for: trackID), FileManager.default.fileExists(atPath: local.path) { return (local, .cached) }
        let server = try await authentication.currentServer()
        let token = try await authentication.validAccessToken()
        guard let ticket = try await tickets.tickets(server: server, accessToken: token, trackIDs: [trackID]).first,
              ticket.expiresAt > Date() else { throw PlaybackCoordinatorError.expiredTicket }
        return (ticket.url, .remote)
    }

    private func consumeEngineEvents() async {
        for await event in engine.events { await apply(event) }
    }

    private func apply(_ event: PlaybackEngineEvent) async {
        switch event {
        case .ready(let value):
            guard phase == .preparing else { return }
            isPrepared = true
            duration = value ?? queue[safe: index]?.track.durationSeconds
            if let pendingSeek { self.pendingSeek = nil; position = min(pendingSeek, duration ?? pendingSeek); await engine.seek(to: position) }
            phase = .paused; emit(); await persist()
            if wantsPlayback { await engine.play() }
        case .time(let value, let total):
            guard phase != .idle && phase != .preparing else { return }
            position = max(value, 0); duration = total ?? duration; emit()
            if abs(position - lastCheckpointPosition) >= 15 { lastCheckpointPosition = position; await learning?.record(.checkpoint(positionSeconds: position, durationSeconds: duration)); await persist() }
        case .playing:
            if learningTrackID != queue[safe: index]?.track.id, let track = queue[safe: index]?.track {
                learningTrackID = track.id; await learning?.record(.started(track: track, positionSeconds: position))
            } else { await learning?.record(.resumed(positionSeconds: position)) }
            phase = .playing; emit(); await persist()
        case .paused: if phase != .interrupted { phase = .paused }; await learning?.record(.paused(positionSeconds: position)); emit(); await persist()
        case .ended:
            if learningTrackID != nil { await learning?.record(.ended(positionSeconds: position, durationSeconds: duration, reason: .completed)); learningTrackID = nil }
            if index + 1 < queue.count { await next() }
            else { wantsPlayback = false; phase = .paused; position = duration ?? position; emit(); await persist() }
        case .stalled: phase = .buffering; emit()
        case .failed: await learning?.record(.technicalFailure(positionSeconds: position)); learningTrackID = nil; phase = .failed; wantsPlayback = false; failureMessage = "Playback stopped unexpectedly."; emit()
        case .interruptionBegan:
            resumeAfterInterruption = phase == .playing; phase = .interrupted; await engine.pause(); emit()
        case .interruptionEnded(let shouldResume):
            phase = .paused; emit()
            if resumeAfterInterruption && shouldResume && wantsPlayback { await engine.play() }
            resumeAfterInterruption = false
        case .routeOutputLost: wantsPlayback = false; phase = .paused; await engine.pause(); await learning?.record(.paused(positionSeconds: position)); emit(); await persist()
        }
    }

    private func handle(_ command: PlaybackCommand) async {
        switch command {
        case .play: await play(); case .pause: await pause(); case .next: await next(); case .previous: await previous()
        case .seek(let seconds): await seek(to: seconds); case .skip(let seconds): await skip(by: seconds)
        }
    }

    private func emit() {
        continuation.yield(makeSnapshot())
    }

    private func makeSnapshot() -> PlaybackSnapshot {
        .init(phase: phase, track: queue[safe: index]?.track, positionSeconds: position, queueCount: max(queue.count - index - 1, 0), canGoNext: index + 1 < queue.count, canGoPrevious: index > 0 || position > 0, failureMessage: failureMessage, queue: queue, currentQueueItemID: queue[safe: index]?.id)
    }

    private func persist() async {
        guard queue.indices.contains(index) else { try? await snapshotStore.remove(); return }
        let value = DurableQueueSnapshot(items: queue, currentIndex: index, positionSeconds: position, sourceIdentity: sourceIdentity)
        do { try await snapshotStore.save(value) }
        catch { logger.error("queue_checkpoint_failed", fields: []) }
    }

    private func firstAutomaticUpcomingIndex() -> Int {
        queue[(min(index + 1, queue.count))...].firstIndex(where: { $0.origin == .automatic }) ?? queue.count
    }

    private func normalizeUpcomingPriority() {
        guard index + 1 < queue.count else { return }
        let prefix = Array(queue[...index])
        let upcoming = queue[(index + 1)...]
        queue = prefix + upcoming.filter { $0.origin == .manual } + upcoming.filter { $0.origin == .automatic }
    }

    private func maybeRefill() async {
        guard let automaticQueueProvider, !isRefilling else { return }
        let remaining = max(queue.count - index - 1, 0)
        guard remaining <= 8 else { return }
        isRefilling = true
        let requested = max(25 - remaining, 0)
        let existingIDs = Set(queue.map { $0.track.id })
        let tracks = await automaticQueueProvider.automaticTracks(excluding: existingIDs, count: requested, at: Date())
        var seen = existingIDs
        queue.append(contentsOf: tracks.filter { seen.insert($0.id).inserted }.map { QueueItem(track: $0, origin: .automatic) })
        normalizeUpcomingPriority(); isRefilling = false; emit()
    }
}

public actor EmptyMediaCache: CachedMediaLocating {
    public init() {}
    public func cachedFile(for trackID: UUID) async -> URL? { nil }
    public func setCurrentlyPlaying(trackID: UUID?) async {}
}

public enum PlaybackCoordinatorError: Error { case expiredTicket }

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
