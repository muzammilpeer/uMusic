import Foundation
import Testing
@testable import PlaybackRestoreProbe

private struct MemorySnapshotStore: PlaybackSnapshotReading {
    let snapshot: PlaybackSnapshot?
    func read() throws -> PlaybackSnapshot? { snapshot }
}

@MainActor
private final class ControlledPlayer: PlayerPreparing {
    var rate: Float = 0
    var currentPositionSeconds: Double = 0
    var continuation: CheckedContinuation<Void, Error>?
    var preparationError: Error?

    func prepare(url: URL, positionSeconds: Double) async throws {
        if let preparationError { throw preparationError }
        try await withCheckedThrowingContinuation { continuation = $0 }
        currentPositionSeconds = positionSeconds
    }

    func completePreparation() { continuation?.resume(); continuation = nil }
    func play() { rate = 1 }
    func pause() { rate = 0 }
}

private func fixtureSnapshot(url: URL = URL(fileURLWithPath: "/tmp/probe.mp3")) -> PlaybackSnapshot {
    PlaybackSnapshot(
        trackID: UUID(),
        title: "Fixture",
        artist: "Test",
        mediaURL: url,
        positionSeconds: 42.25,
        queueTrackIDs: [UUID(), UUID()]
    )
}

@Suite(.serialized)
@MainActor
struct PlaybackRestorerTests {
    @Test("One hundred launches publish the saved snapshot without autoplay")
    func snapshotIsImmediateAndPaused() throws {
        for _ in 0..<100 {
            let player = ControlledPlayer()
            let snapshot = fixtureSnapshot()
            let start = ContinuousClock.now
            let restorer = try PlaybackRestorer(
                store: MemorySnapshotStore(snapshot: snapshot),
                player: player
            )
            let elapsed = start.duration(to: .now)

            #expect(restorer.state == .snapshot(snapshot))
            #expect(player.rate == 0)
            #expect(elapsed < .milliseconds(300))
        }
    }

    @Test("A play request made during preparation is honored only after readiness")
    func earlyPlayIsDeferred() async throws {
        let player = ControlledPlayer()
        let snapshot = fixtureSnapshot()
        let restorer = try PlaybackRestorer(
            store: MemorySnapshotStore(snapshot: snapshot),
            player: player
        )

        let preparation = Task { await restorer.prepareRestoredMedia() }
        await Task.yield()
        restorer.play()
        #expect(player.rate == 0)

        player.completePreparation()
        await preparation.value

        #expect(player.rate == 1)
        #expect(restorer.state == .playing(snapshot))
        #expect(abs(player.currentPositionSeconds - snapshot.positionSeconds) < 0.5)
    }

    @Test("Missing media becomes a recoverable failed state")
    func missingMediaFailsWithoutPlaying() async throws {
        let player = ControlledPlayer()
        player.preparationError = PlaybackPreparationError.mediaUnavailable
        let snapshot = fixtureSnapshot()
        let restorer = try PlaybackRestorer(
            store: MemorySnapshotStore(snapshot: snapshot),
            player: player
        )

        await restorer.prepareRestoredMedia()

        guard case let .failed(failedSnapshot, _) = restorer.state else {
            Issue.record("Expected a failed restoration state")
            return
        }
        #expect(failedSnapshot == snapshot)
        #expect(player.rate == 0)
    }
}

