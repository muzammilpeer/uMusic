import AVFoundation
import Foundation
import MediaPlayer

@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    @Published private(set) var current: Track?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var volume: Double = 1
    @Published private(set) var errorMessage: String?
    @Published private(set) var audioRouteName = "Built-in Audio"
    @Published private(set) var headsetBatteryStatus = "No Bluetooth headset connected"

    private let player = AVPlayer()
    private let events: EventSyncService
    private let queueStore: QueueStore
    private var server: URL?
    private var token: String?
    private var playbackID = UUID()
    private var timeObserver: Any?
    private var lastHeartbeatSeconds = 0
    private var continuationTask: Task<Void, Never>?
    private var eventFlushTask: Task<Void, Never>?
    private var lastContinuationAttempt = Date.distantPast
    private var continuationThreshold = 3
    private var continuationProvider: (([UUID]) async -> [Track])?
    private var offlineURLProvider: ((UUID) async -> URL?)?
    private var currentIsOffline = false
    private var contextSnapshotID: UUID?
    private var didRestoreCurrent = false
    private var isRestoringCurrent = false
    private var resumeWhenRestored = false
    private let offlineManager: OfflineManager

    init(
        events: EventSyncService = EventSyncService(),
        queueStore: QueueStore = QueueStore(),
        offlineManager: OfflineManager = .shared
    ) {
        self.events = events
        self.queueStore = queueStore
        self.offlineManager = offlineManager
        super.init()
        configureAudioSession()
        updateAudioRoute()
        observeAudioChanges()
        configureRemoteCommands()
        restoreQueue()
        observeTime()
        observePlayback()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    func configure(server: URL, token: String) {
        self.server = server
        self.token = token
        scheduleEventFlush()
        restoreCurrentIfNeeded()
    }

    func play(_ track: Track, in tracks: [Track]? = nil) {
        Task { [weak self] in
            guard let self else { return }
            if let localURL = await self.offlineManager.localURL(for: track.id) {
                self.playOffline(track, url: localURL, in: tracks ?? self.queue)
            } else {
                guard let server = self.server, let token = self.token else { return }
                do {
                    let refreshed = try await APIClient().track(
                        server: server, token: token, trackID: track.id
                    )
                    self.playOnline(refreshed, in: tracks)
                } catch {
                    self.errorMessage = "This song could not get a fresh playback link. Check the connection and try again."
                }
            }
        }
    }

    private func playOnline(_ track: Track, in tracks: [Track]? = nil) {
        guard let server else { return }
        let authenticatedURL = URL(string: track.streamPath, relativeTo: server)?.absoluteURL
        guard let url = track.streamURL ?? authenticatedURL else { return }
        if let tracks {
            queue = tracks.map { $0.id == track.id ? track : $0 }
        } else if let index = queue.firstIndex(where: { $0.id == track.id }) {
            queue[index] = track
        } else {
            queue.append(track)
        }
        current = track
        currentIsOffline = false
        playbackID = UUID()
        lastHeartbeatSeconds = 0
        elapsed = 0
        errorMessage = nil
        let asset: AVURLAsset
        if track.streamURL != nil {
            asset = AVURLAsset(url: url)
        } else if let token {
            asset = AVURLAsset(
                url: url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]]
            )
        } else {
            return
        }
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        player.play()
        isPlaying = true
        persistQueue()
        persistPlaybackState()
        updateNowPlaying()
        record(type: "started", listenedDelta: 0)
    }

    func playOffline(_ track: Track, url: URL, in tracks: [Track]) {
        queue = tracks
        current = track
        currentIsOffline = true
        playbackID = UUID()
        lastHeartbeatSeconds = 0
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
        isPlaying = true
        persistQueue()
        persistPlaybackState()
        updateNowPlaying()
        record(type: "started", listenedDelta: 0)
    }

    func setPreparedQueue(_ tracks: [Track]) {
        queue = tracks
        persistQueue()
    }

    func configureContinuation(
        threshold: Int,
        provider: @escaping ([UUID]) async -> [Track]
    ) {
        continuationThreshold = max(1, threshold)
        continuationProvider = provider
    }

    func configureOfflineURLs(provider: @escaping (UUID) async -> URL?) {
        offlineURLProvider = provider
    }

    func rerankFutureTracks(targetEnergy: Double, limit: Int = 8) {
        guard let current else { return }
        queue = FutureQueueReranker.rerank(
            queue, after: current.id, targetEnergy: targetEnergy, limit: limit
        )
        persistQueue()
    }

    func configureContext(snapshotID: UUID) { contextSnapshotID = snapshotID }

    func toggle() {
        if current != nil,
           isRestoringCurrent || player.currentItem == nil || player.currentItem?.status == .failed {
            resumeWhenRestored = true
            restoreCurrentIfNeeded(force: player.currentItem?.status == .failed)
            return
        }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        updateNowPlaying()
        record(type: isPlaying ? "resumed" : "paused", listenedDelta: 0)
        persistPlaybackState()
    }

    func next() {
        guard let current, let index = queue.firstIndex(of: current), index + 1 < queue.count else {
            return
        }
        record(type: "completed", listenedDelta: 0)
        playPreferred(queue[index + 1])
    }

    func previous() {
        guard let current, let index = queue.firstIndex(of: current), index > 0 else { return }
        playPreferred(queue[index - 1])
    }


    private func playPreferred(_ track: Track) {
        guard let offlineURLProvider else { play(track); return }
        Task { [weak self] in
            guard let self else { return }
            if let url = await offlineURLProvider(track.id) {
                self.playOffline(track, url: url, in: self.queue)
            } else {
                self.play(track)
            }
        }
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 1_000))
        elapsed = max(0, seconds)
        updateNowPlaying()
        record(type: "seeked", listenedDelta: 0)
        persistPlaybackState()
    }

    func setVolume(_ newValue: Double) {
        volume = min(max(newValue, 0), 1)
        player.volume = Float(volume)
    }

    private func observePlayback() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self, notification.object as? AVPlayerItem === self.player.currentItem else { return }
                self.next()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self, notification.object as? AVPlayerItem === self.player.currentItem else { return }
                self.isPlaying = false
                self.errorMessage = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
                    ?? "This song could not be played. Refresh the library and try again."
            }
        }
    }

    private func observeTime() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = time.seconds.isFinite ? time.seconds : 0
                let second = Int(self.elapsed)
                if self.isPlaying, second - self.lastHeartbeatSeconds >= 15 {
                    self.lastHeartbeatSeconds = second
                    self.record(type: "progress", listenedDelta: 15_000)
                    self.updateNowPlaying()
                    self.refillQueueIfNeeded()
                    self.persistPlaybackState()
                }
            }
        }
    }

    private func refillQueueIfNeeded() {
        guard continuationTask == nil,
              Date().timeIntervalSince(lastContinuationAttempt) >= 60,
              let current,
              let index = queue.firstIndex(of: current),
              queue.count - index - 1 <= continuationThreshold,
              let continuationProvider else { return }
        lastContinuationAttempt = Date()
        let existing = queue.map(\.id)
        continuationTask = Task { [weak self] in
            let additions = await continuationProvider(existing)
            guard let self else { return }
            let known = Set(self.queue.map(\.id))
            self.queue.append(contentsOf: additions.filter { !known.contains($0.id) })
            self.persistQueue()
            self.continuationTask = nil
        }
    }

    private func record(type: String, listenedDelta: Int) {
        guard let current else { return }
        var event = ListeningEvent(
            clientEventID: UUID(),
            playbackID: playbackID,
            trackID: current.id,
            eventType: type,
            clientTimestamp: Date(),
            positionMS: Int(elapsed * 1_000),
            durationMS: current.durationMS,
            listenedMSDelta: listenedDelta,
            offline: currentIsOffline
        )
        event.contextSnapshotID = contextSnapshotID
        Task {
            await events.append(event)
            if type == "paused" || type == "completed" {
                await flushEvents()
            } else {
                await MainActor.run { self.scheduleEventFlush() }
            }
        }
    }

    private func scheduleEventFlush() {
        guard eventFlushTask == nil, server != nil, token != nil else { return }
        eventFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppEnergyPolicy.lowEnergyEnabled ? 120 : 60))
            guard !Task.isCancelled, let self else { return }
            await self.flushEvents()
        }
    }

    private func flushEvents() async {
        eventFlushTask?.cancel()
        eventFlushTask = nil
        guard let server, let token else { return }
        try? await events.flush(server: server, token: token)
    }

    private func configureAudioSession() {
        #if os(iOS)
        Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
        }
        #endif
    }

    private func observeAudioChanges() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        #endif
    }

    #if os(iOS)
    @objc private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }
        if type == .began {
            player.pause()
            isPlaying = false
            record(type: "paused", listenedDelta: 0)
            updateNowPlaying()
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        updateAudioRoute()
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
        else { return }
        player.pause()
        isPlaying = false
        record(type: "paused", listenedDelta: 0)
        updateNowPlaying()
    }
    #endif

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !self.isPlaying { self.toggle() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in self?.player.pause(); self?.isPlaying = false; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let position = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: position.positionTime)
            return .success
        }
        commands.skipForwardCommand.preferredIntervals = [15]
        commands.skipBackwardCommand.preferredIntervals = [15]
        commands.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.seek(to: self.elapsed + 15)
            return .success
        }
        commands.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.seek(to: self.elapsed - 15)
            return .success
        }
    }

    private func updateAudioRoute() {
        #if os(iOS)
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        audioRouteName = outputs.map(\.portName).joined(separator: ", ")
        if audioRouteName.isEmpty { audioRouteName = "Built-in Audio" }
        let bluetoothPorts: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
        headsetBatteryStatus = outputs.contains { bluetoothPorts.contains($0.portType) }
            ? "Shown by iOS in Control Center"
            : "No Bluetooth headset connected"
        #else
        audioRouteName = "Mac Audio Output"
        headsetBatteryStatus = "Shown by macOS in Control Center"
        #endif
    }

    private func updateNowPlaying() {
        guard let current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist.name,
            MPMediaItemPropertyAlbumTitle: HealthWorkoutService.shared.active
                ? HealthWorkoutService.shared.activityName : (current.album?.title ?? "uMusic"),
            MPMediaItemPropertyPlaybackDuration: Double(current.durationMS) / 1_000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }

    private func persistQueue() {
        queueStore.save(queue)
    }

    func persistPlaybackState() {
        guard let current else { return }
        queueStore.savePlayback(.init(
            trackID: current.id,
            track: current,
            elapsed: elapsed,
            wasPlaying: isPlaying,
            wasOffline: currentIsOffline
        ))
    }

    private func restoreQueue() {
        queue = queueStore.load()
        guard let state = queueStore.loadPlayback(),
              let restored = state.track ?? queue.first(where: { $0.id == state.trackID }) else {
            return
        }
        current = restored
        if !queue.contains(where: { $0.id == restored.id }) { queue.insert(restored, at: 0) }
        elapsed = min(max(0, state.elapsed), Double(restored.durationMS) / 1_000)
        currentIsOffline = state.wasOffline
        isPlaying = false
    }

    private func restoreCurrentIfNeeded(force: Bool = false) {
        if force {
            didRestoreCurrent = false
            player.replaceCurrentItem(with: nil)
        }
        guard !didRestoreCurrent, !isRestoringCurrent, let server, let token,
              let state = queueStore.loadPlayback(),
              let track = state.track ?? queue.first(where: { $0.id == state.trackID }) else { return }
        didRestoreCurrent = true
        isRestoringCurrent = true
        errorMessage = "Preparing saved song…"
        Task { [weak self] in
            guard let self else { return }
            defer { self.isRestoringCurrent = false }
            let localURL = await self.offlineManager.localURL(for: track.id)
            let asset: AVURLAsset
            var playbackTrack = track
            if let localURL {
                asset = AVURLAsset(url: localURL)
                self.currentIsOffline = true
            } else {
                guard let refreshed = try? await APIClient().track(
                    server: server, token: token, trackID: track.id
                ), let url = refreshed.streamURL else {
                    self.didRestoreCurrent = false
                    self.errorMessage = "The saved song could not get a fresh playback link. Check the connection and try again."
                    return
                }
                asset = AVURLAsset(url: url)
                self.currentIsOffline = false
                playbackTrack = refreshed
            }
            do {
                guard try await asset.load(.isPlayable) else {
                    throw URLError(.cannotDecodeContentData)
                }
            } catch {
                self.didRestoreCurrent = false
                self.errorMessage = "The saved song could not be prepared. Check the connection or download it again."
                return
            }
            self.current = playbackTrack
            if let index = self.queue.firstIndex(where: { $0.id == playbackTrack.id }) {
                self.queue[index] = playbackTrack
            }
            let duration = Double(playbackTrack.durationMS) / 1_000
            let savedPosition = min(max(0, state.elapsed), duration)
            self.elapsed = duration - savedPosition <= 5 ? 0 : savedPosition
            self.player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            await self.player.seek(
                to: CMTime(seconds: self.elapsed, preferredTimescale: 1_000)
            )
            self.errorMessage = nil
            if self.resumeWhenRestored {
                self.player.play()
                self.isPlaying = true
                self.resumeWhenRestored = false
                self.record(type: "resumed", listenedDelta: 0)
            } else {
                // Restore safely in a paused state; the user decides when playback resumes.
                self.isPlaying = false
            }
            self.updateNowPlaying()
        }
    }
}
