import Foundation

public enum QueuePlacement: String, Codable, Sendable {
    case now
    case next
    case later
}

public protocol PlaybackControlling: Sendable {
    var snapshots: AsyncStream<PlaybackSnapshot> { get }
    func play() async
    func pause() async
    func enqueue(trackID: UUID, placement: QueuePlacement) async
    func enqueue(_ track: TrackSummary, placement: QueuePlacement, origin: QueueItemOrigin) async
    func setQueue(_ tracks: [TrackSummary], startingAt index: Int) async
    func setAutomaticQueue(_ tracks: [TrackSummary], startingAt index: Int) async
    func removeQueueItem(id: UUID) async
    func moveQueueItems(fromOffsets: IndexSet, toOffset: Int) async
    func checkpoint() async
    func next() async
    func previous() async
    func seek(to seconds: Double) async
    func skip(by seconds: Double) async
}

public protocol QueueSnapshotStoring: Sendable {
    func save(_ snapshot: DurableQueueSnapshot) async throws
    func remove() async throws
}

public protocol PlaybackTicketAPI: Sendable {
    func tickets(server: ServerConfiguration, accessToken: String, trackIDs: [UUID]) async throws -> [PlaybackTicket]
}

public protocol CachedMediaLocating: Sendable {
    func cachedFile(for trackID: UUID) async -> URL?
    func setCurrentlyPlaying(trackID: UUID?) async
}

@MainActor public protocol MediaPlaybackEngine: Sendable {
    nonisolated var events: AsyncStream<PlaybackEngineEvent> { get }
    func prepare(url: URL) async throws
    func play() async
    func pause() async
    func seek(to seconds: Double) async
    func configure(track: TrackSummary?, commandHandler: @escaping @Sendable (PlaybackCommand) -> Void) async
}

public protocol LibraryProviding: Sendable {
    var snapshots: AsyncStream<LibrarySnapshot> { get }
    func sync() async throws
    func browse(_ query: LibraryQuery) async throws -> [TrackSummary]
}

public protocol PlaylistManaging: Sendable {
    func playlists() async throws -> [PlaylistSummary]
    func playlist(id: UUID) async throws -> ManualPlaylist
    func createPlaylist(name: String) async throws -> ManualPlaylist
    func renamePlaylist(id: UUID, name: String, expectedRevision: Int64) async throws -> ManualPlaylist
    func deletePlaylist(id: UUID, expectedRevision: Int64) async throws
    func addTrack(_ track: TrackSummary, to playlistID: UUID, expectedRevision: Int64) async throws -> ManualPlaylist
    func removeTrack(at index: Int, from playlistID: UUID, expectedRevision: Int64) async throws -> ManualPlaylist
    func setAutomaticallyGrows(_ enabled: Bool, for playlistID: UUID, expectedRevision: Int64) async throws -> ManualPlaylist
}

public protocol PersonalizationManaging: Sendable {
    func recommendedQueue(from tracks: [TrackSummary], at date: Date, limit: Int) async -> [TrackSummary]
    func recommendations(from tracks: [TrackSummary], at date: Date, offlineTrackIDs: Set<UUID>, excluding trackIDs: Set<UUID>, limit: Int) async -> RecommendationResult
    func recentHistory(lastCalendarDays: Int, now: Date, calendar: Calendar) async -> [ListeningHistoryDay]
    func learningSnapshot() async -> LearningSnapshot
    func setRawHistoryRetention(_ retention: RawHistoryRetention) async throws
    func deleteHistory() async throws
    func exportSanitized() async throws -> URL
    func previewFullResearchExport() async -> ResearchExportPreview
    func exportResearch(_ kind: ResearchExportKind, confirmationID: UUID?) async throws -> URL
    func cleanupResearchExports() async
    func resetLearning() async throws
}

public protocol OfflineManaging: Sendable {
    func storageSnapshot() async -> OfflineStorageSnapshot
    func download(_ track: TrackSummary, retention: OfflineRetention) async throws
    func removeDownload(trackID: UUID) async throws
    func setQuota(bytes: Int64) async throws
    func setAllowsCellular(_ allowed: Bool) async
    func reconcile() async
}

public protocol DiagnosticsProviding: Sendable {
    func snapshot() async -> DiagnosticsSnapshot
}

public protocol UMusicClient: Sendable {
    var authentication: any AuthenticationManaging { get }
    var playback: any PlaybackControlling { get }
    var library: any LibraryProviding { get }
    var playlists: any PlaylistManaging { get }
    var personalization: any PersonalizationManaging { get }
    var offline: any OfflineManaging { get }
    var diagnostics: any DiagnosticsProviding { get }
    var context: any ContextManaging { get }
    var calendarPreferences: any CalendarPreferenceManaging { get }
}
