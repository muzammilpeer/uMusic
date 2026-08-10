@preconcurrency import AVFoundation
import Foundation
@preconcurrency import MediaPlayer
import UMusicDomain

@MainActor
public final class SystemPlaybackEngine: MediaPlaybackEngine, @unchecked Sendable {
    public nonisolated let events: AsyncStream<PlaybackEngineEvent>
    private let continuation: AsyncStream<PlaybackEngineEvent>.Continuation
    private let player = AVPlayer()
    private var periodicObserver: Any?
    private var endObserver: NSObjectProtocol?
#if os(iOS)
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
#endif

    public init() {
        let stream = AsyncStream<PlaybackEngineEvent>.makeStream(bufferingPolicy: .bufferingNewest(4))
        events = stream.stream
        continuation = stream.continuation
        periodicObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            let duration = self.player.currentItem?.duration.seconds
            self.continuation.yield(.time(position: max(time.seconds, 0), duration: duration?.isFinite == true ? duration : nil))
        }
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began { self?.continuation.yield(.interruptionBegan) }
            else {
                let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
                self?.continuation.yield(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
            }
        }
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            self?.continuation.yield(.routeOutputLost)
        }
#endif
    }

    isolated deinit {
        if let periodicObserver { player.removeTimeObserver(periodicObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
#if os(iOS)
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
#endif
        continuation.finish()
    }

    public func prepare(url: URL) async throws {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        let item = AVPlayerItem(url: url)
        guard try await item.asset.load(.isPlayable) else { throw AVPlayerPlaybackError.unplayable }
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in self?.continuation.yield(.ended) }
        let duration = try? await item.asset.load(.duration).seconds
        continuation.yield(.ready(duration: duration?.isFinite == true ? duration : nil))
    }

    public func play() async {
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
#endif
        player.play()
        continuation.yield(.playing)
    }

    public func pause() async { player.pause(); continuation.yield(.paused) }
    public func seek(to seconds: Double) async { await player.seek(to: CMTime(seconds: max(seconds, 0), preferredTimescale: 600)) }

    public func configure(track: TrackSummary?, commandHandler: @escaping @Sendable (PlaybackCommand) -> Void) async {
        let center = MPRemoteCommandCenter.shared()
        [center.playCommand, center.pauseCommand, center.nextTrackCommand, center.previousTrackCommand, center.skipForwardCommand, center.skipBackwardCommand, center.changePlaybackPositionCommand].forEach { $0.removeTarget(nil) }
        center.playCommand.addTarget { _ in commandHandler(.play); return .success }
        center.pauseCommand.addTarget { _ in commandHandler(.pause); return .success }
        center.nextTrackCommand.addTarget { _ in commandHandler(.next); return .success }
        center.previousTrackCommand.addTarget { _ in commandHandler(.previous); return .success }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { _ in commandHandler(.skip(seconds: 15)); return .success }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { _ in commandHandler(.skip(seconds: -15)); return .success }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            commandHandler(.seek(seconds: event.positionTime)); return .success
        }
        if let track {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyTitle: track.title,
                MPMediaItemPropertyArtist: track.artist,
                MPMediaItemPropertyPlaybackDuration: track.durationSeconds as Any,
            ]
        } else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    }
}

public enum AVPlayerPlaybackError: Error { case unplayable }
