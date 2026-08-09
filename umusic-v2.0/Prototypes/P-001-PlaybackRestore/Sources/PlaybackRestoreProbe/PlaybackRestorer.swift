import AVFoundation
import Foundation

public enum RestorationState: Equatable, Sendable {
    case empty
    case snapshot(PlaybackSnapshot)
    case preparing(PlaybackSnapshot)
    case ready(PlaybackSnapshot)
    case playing(PlaybackSnapshot)
    case failed(PlaybackSnapshot, message: String)
}

@MainActor
public protocol PlayerPreparing: AnyObject {
    var rate: Float { get }
    var currentPositionSeconds: Double { get }
    func prepare(url: URL, positionSeconds: Double) async throws
    func play()
    func pause()
}

public enum PlaybackPreparationError: Error, Equatable {
    case mediaUnavailable
    case itemFailed
}

@MainActor
public final class PlaybackRestorer {
    public private(set) var state: RestorationState = .empty
    private let player: PlayerPreparing
    private var playWhenReady = false

    public init(store: PlaybackSnapshotReading, player: PlayerPreparing) throws {
        self.player = player
        if let snapshot = try store.read() {
            state = .snapshot(snapshot)
        }
    }

    public func prepareRestoredMedia() async {
        guard case let .snapshot(snapshot) = state else { return }
        state = .preparing(snapshot)

        do {
            try await player.prepare(
                url: snapshot.mediaURL,
                positionSeconds: snapshot.positionSeconds
            )
            state = .ready(snapshot)
            if playWhenReady {
                player.play()
                state = .playing(snapshot)
            } else {
                player.pause()
            }
        } catch {
            state = .failed(snapshot, message: String(describing: error))
        }
    }

    public func play() {
        switch state {
        case let .ready(snapshot):
            player.play()
            state = .playing(snapshot)
        case .snapshot, .preparing:
            playWhenReady = true
        default:
            break
        }
    }
}

@MainActor
public final class AVPlayerPreparationAdapter: PlayerPreparing {
    private let player = AVPlayer()

    public init() {}

    public var rate: Float { player.rate }

    public var currentPositionSeconds: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    public func prepare(url: URL, positionSeconds: Double) async throws {
        guard !url.isFileURL || FileManager.default.fileExists(atPath: url.path) else {
            throw PlaybackPreparationError.mediaUnavailable
        }

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.pause()

        do {
            let status = try await item.asset.load(.isPlayable)
            guard status else { throw PlaybackPreparationError.itemFailed }
            let target = CMTime(seconds: positionSeconds, preferredTimescale: 600)
            await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            player.pause()
        } catch let error as PlaybackPreparationError {
            throw error
        } catch {
            throw PlaybackPreparationError.itemFailed
        }
    }

    public func play() { player.play() }
    public func pause() { player.pause() }
}
