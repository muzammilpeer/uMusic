import Foundation
import UMusicDomain

public actor PlaceholderAuthenticationManager: AuthenticationManaging {
    public nonisolated let snapshots: AsyncStream<AuthenticationState>
    public init() {
        snapshots = AsyncStream { continuation in continuation.yield(.signedOut); continuation.finish() }
    }
    public func restore() async {}
    public func connect(serverURL: String, username: String, password: String, keepSignedIn: Bool, allowsInsecureLocalhost: Bool) async {}
    public func validAccessToken() async throws -> String { throw AuthenticationCoordinatorError.noSession }
    public func currentServer() async throws -> ServerConfiguration { throw AuthenticationCoordinatorError.noSession }
    public func logout(localData: LogoutLocalDataDisposition) async {}
}

public actor PlaceholderPlaybackController: PlaybackControlling {
    public nonisolated let snapshots: AsyncStream<PlaybackSnapshot>

    public init(initial: PlaybackSnapshot = .idle) {
        snapshots = AsyncStream { continuation in
            continuation.yield(initial)
            continuation.finish()
        }
    }

    public func play() async {}
    public func pause() async {}
    public func enqueue(trackID: UUID, placement: QueuePlacement) async {}
    public func enqueue(_ track: TrackSummary, placement: QueuePlacement, origin: QueueItemOrigin) async {}
    public func setQueue(_ tracks: [TrackSummary], startingAt index: Int) async {}
    public func setAutomaticQueue(_ tracks: [TrackSummary], startingAt index: Int) async {}
    public func removeQueueItem(id: UUID) async {}
    public func moveQueueItems(fromOffsets: IndexSet, toOffset: Int) async {}
    public func checkpoint() async {}
    public func next() async {}
    public func previous() async {}
    public func seek(to seconds: Double) async {}
    public func skip(by seconds: Double) async {}
}

public actor PlaceholderLibraryProvider: LibraryProviding {
    public nonisolated let snapshots: AsyncStream<LibrarySnapshot>

    public init(initial: LibrarySnapshot = .empty) {
        snapshots = AsyncStream { continuation in
            continuation.yield(initial)
            continuation.finish()
        }
    }

    public func sync() async throws {}
    public func browse(_ query: LibraryQuery) async throws -> [TrackSummary] { [] }
}

public actor PlaceholderPlaylistManager: PlaylistManaging {
    public init() {}
    public func playlists() async throws -> [PlaylistSummary] { [] }
    public func playlist(id: UUID) async throws -> ManualPlaylist { throw PlaylistStoreError.notFound }
    public func createPlaylist(name: String) async throws -> ManualPlaylist { ManualPlaylist(name: name) }
    public func renamePlaylist(id: UUID, name: String, expectedRevision: Int64) async throws -> ManualPlaylist { throw PlaylistStoreError.notFound }
    public func deletePlaylist(id: UUID, expectedRevision: Int64) async throws {}
    public func addTrack(_ track: TrackSummary, to playlistID: UUID, expectedRevision: Int64) async throws -> ManualPlaylist { throw PlaylistStoreError.notFound }
    public func removeTrack(at index: Int, from playlistID: UUID, expectedRevision: Int64) async throws -> ManualPlaylist { throw PlaylistStoreError.notFound }
    public func setAutomaticallyGrows(_ enabled: Bool, for playlistID: UUID, expectedRevision: Int64) async throws -> ManualPlaylist { throw PlaylistStoreError.notFound }
}

public actor PlaceholderCalendarPreferenceManager: CalendarPreferenceManaging {
    public init() {}
    public func snapshot() async -> CalendarPreferenceSnapshot { .init() }
    public func setPreference(_ preference: RamadanPreference, selectedPlaylistID: UUID?) async throws {}
    public func setCalendarWindow(_ window: CalendarWindow?) async throws {}
    public func setInstantOverride(_ active: Bool?) async throws {}
    public func setRule(_ rule: SmartPlaylistRule) async throws {}
    public func preferredPlaylist(at date: Date) async -> ManualPlaylist? { nil }
    public func suggestedPlaylist(at date: Date) async -> ManualPlaylist? { nil }
    public func evaluateSmartPlaylists(at date: Date, calendar: Calendar) async throws {}
    public func approve(auditID: UUID, at date: Date) async throws {}
    public func undo(auditID: UUID, at date: Date) async throws {}
}

public actor PlaceholderPersonalizationManager: PersonalizationManaging {
    public init() {}
    public func recommendedQueue(from tracks: [TrackSummary], at date: Date, limit: Int) async -> [TrackSummary] {
        guard !tracks.isEmpty, limit > 0 else { return [] }
        let ordered = tracks.sorted {
            if $0.id.uuidString != $1.id.uuidString { return $0.id.uuidString < $1.id.uuidString }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        let hour = Calendar(identifier: .gregorian).component(.hour, from: date)
        let offset = hour % ordered.count
        let rotated = Array(ordered[offset...]) + Array(ordered[..<offset])
        return Array(rotated.prefix(limit))
    }
    public func recentHistory(lastCalendarDays: Int, now: Date, calendar: Calendar) async -> [ListeningHistoryDay] { [] }
    public func recommendations(from tracks: [TrackSummary], at date: Date, offlineTrackIDs: Set<UUID>, excluding trackIDs: Set<UUID>, limit: Int) async -> RecommendationResult {
        let selected = await recommendedQueue(from: tracks.filter { !trackIDs.contains($0.id) }, at: date, limit: limit)
        return RecommendationResult(engineVersion: "placeholder", generatedAt: date, items: selected.map { RecommendedTrack(track: $0, score: 0, reasons: [.coldStartDiversity]) })
    }
    public func learningSnapshot() async -> LearningSnapshot { LearningSnapshot(retention: .ninetyDays, eventCount: 0, observationCount: 0, aggregateCount: 0, lastReducedSequence: 0) }
    public func setRawHistoryRetention(_ retention: RawHistoryRetention) async throws {}
    public func deleteHistory() async throws {}
    public func exportSanitized() async throws -> URL { FileManager.default.temporaryDirectory.appending(path: "umusic-empty-export.json") }
    public func previewFullResearchExport() async -> ResearchExportPreview { .init(eventCount: 0, observationCount: 0, includesTrackMetadata: true, sensitiveCategories: [], expiresAt: Date().addingTimeInterval(300)) }
    public func exportResearch(_ kind: ResearchExportKind, confirmationID: UUID?) async throws -> URL { FileManager.default.temporaryDirectory.appending(path: "umusic-empty-export.umusicresearch") }
    public func cleanupResearchExports() async {}
    public func resetLearning() async throws {}
}

public actor PlaceholderOfflineManager: OfflineManaging {
    public init() {}
    public func storageSnapshot() async -> OfflineStorageSnapshot {
        OfflineStorageSnapshot(usedBytes: 0, quotaBytes: 500 * 1_024 * 1_024)
    }
    public func download(_ track: TrackSummary, retention: OfflineRetention) async throws {}
    public func removeDownload(trackID: UUID) async throws {}
    public func setQuota(bytes: Int64) async throws {}
    public func setAllowsCellular(_ allowed: Bool) async {}
    public func reconcile() async {}
}

public actor PlaceholderDiagnosticsProvider: DiagnosticsProviding {
    public init() {}
    public func snapshot() async -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(frameworkVersion: UMusicCoreVersion.current, schemaVersion: 1)
    }
}

public actor PlaceholderContextManager: ContextManaging {
    public nonisolated let snapshots: AsyncStream<ContextSettingsSnapshot>
    private var value = ContextSettingsSnapshot()
    public init() { snapshots = AsyncStream { continuation in continuation.yield(ContextSettingsSnapshot()); continuation.finish() } }
    public func settings() async -> ContextSettingsSnapshot { value }
    public func selectActivity(_ activity: ListeningActivity) async { value = ContextSettingsSnapshot(lowEnergyMode: value.lowEnergyMode, selectedActivity: activity) }
    public func setLowEnergyMode(_ enabled: Bool) async { value = ContextSettingsSnapshot(lowEnergyMode: enabled, selectedActivity: value.selectedActivity) }
    public func setSignal(_ signal: ContextSignal, enabled: Bool) async {}
    public func sampleActivityNow() async throws -> ActivityClassification? { nil }
    public func beginListeningContext() async {}
    public func endListeningContext() async {}
}
