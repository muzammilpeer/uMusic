import Foundation
import UMusicData
import UMusicDomain
import UMusicContext
import UMusicNetworking
import UMusicOffline
import UMusicPlayback
import UMusicSecurity
import UMusicLearning

public enum UMusicCoreVersion {
    public static let current = "2.0.0-alpha.15"
}

public struct DefaultUMusicClient: UMusicClient {
    public let authentication: any AuthenticationManaging
    public let playback: any PlaybackControlling
    public let library: any LibraryProviding
    public let playlists: any PlaylistManaging
    public let personalization: any PersonalizationManaging
    public let offline: any OfflineManaging
    public let diagnostics: any DiagnosticsProviding
    public let context: any ContextManaging
    public let calendarPreferences: any CalendarPreferenceManaging

    public init(
        authentication: any AuthenticationManaging,
        playback: any PlaybackControlling,
        library: any LibraryProviding,
        playlists: any PlaylistManaging,
        personalization: any PersonalizationManaging,
        offline: any OfflineManaging,
        diagnostics: any DiagnosticsProviding,
        context: any ContextManaging,
        calendarPreferences: any CalendarPreferenceManaging
    ) {
        self.authentication = authentication
        self.playback = playback
        self.library = library
        self.playlists = playlists
        self.personalization = personalization
        self.offline = offline
        self.diagnostics = diagnostics
        self.context = context
        self.calendarPreferences = calendarPreferences
    }
}

public enum UMusicCompositionRoot {
    public static func makePlaceholderClient() -> DefaultUMusicClient {
        DefaultUMusicClient(
            authentication: PlaceholderAuthenticationManager(),
            playback: PlaceholderPlaybackController(),
            library: PlaceholderLibraryProvider(),
            playlists: PlaceholderPlaylistManager(),
            personalization: PlaceholderPersonalizationManager(),
            offline: PlaceholderOfflineManager(),
            diagnostics: PlaceholderDiagnosticsProvider(),
            context: PlaceholderContextManager(),
            calendarPreferences: PlaceholderCalendarPreferenceManager()
        )
    }

    @MainActor public static func makeLiveClient(
        defaults: UserDefaults = .standard,
        keychainAccessGroup: String? = nil
    ) -> DefaultUMusicClient {
        let installationKey = "umusic.v2.installation-id"
        let installationID: UUID
        if let stored = defaults.string(forKey: installationKey).flatMap(UUID.init(uuidString:)) {
            installationID = stored
        } else {
            installationID = UUID()
            defaults.set(installationID.uuidString, forKey: installationKey)
        }

#if os(iOS)
        let platform = "ios"
#else
        let platform = "macos"
#endif
        let authentication = AuthenticationCoordinator(
            api: URLSessionAuthenticationAPI(
                installationID: installationID,
                platform: platform,
                appVersion: UMusicCoreVersion.current
            ),
            tokenStore: KeychainSessionTokenStore(accessGroup: keychainAccessGroup),
            configurationStore: UserDefaultsServerConfigurationStore()
        )
        let catalogURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "uMusic-v2", directoryHint: .isDirectory)
            .appending(path: "Catalog.sqlite")
        try? FileManager.default.createDirectory(at: catalogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let library = LibrarySyncCoordinator(
            store: CatalogStore(storeURL: catalogURL),
            api: URLSessionLibraryChangesAPI(),
            authentication: authentication
        )
        let playlists = FilePlaylistStore(url: catalogURL.deletingLastPathComponent().appending(path: "Playlists-v1.json"))
        let offlineRoot = catalogURL.deletingLastPathComponent().appending(path: "Offline", directoryHint: .isDirectory)
        let downloadTransport = BackgroundMediaDownloadTransport(identifier: "uk.muzammilpeer.umusic.v2.media", stagingDirectory: offlineRoot.appending(path: "Staging", directoryHint: .isDirectory))
        let offline = DownloadCoordinator(
            root: offlineRoot,
            transport: downloadTransport,
            tickets: URLSessionPlaybackTicketAPI(),
            authentication: authentication
        )
        Task { await offline.reconcile() }
        let learning = LocalLearningStore(url: catalogURL.deletingLastPathComponent().appending(path: "Learning-v1.json"))
        let context = ContextCoordinator(settingsURL: catalogURL.deletingLastPathComponent().appending(path: "ContextSettings-v1.json"), learning: learning)
        let calendarPreferences = CalendarPlaylistCoordinator(url: catalogURL.deletingLastPathComponent().appending(path: "CalendarPreferences-v1.json"), playlists: playlists, library: library)
        let recommendationQueue = RecommendationQueueProvider(library: library, personalization: learning, offline: offline)
        let playback = PlaybackCoordinator(
            engine: SystemPlaybackEngine(),
            tickets: URLSessionPlaybackTicketAPI(),
            cache: offline,
            authentication: authentication,
            snapshotStore: FileQueueSnapshotStore(url: catalogURL.deletingLastPathComponent().appending(path: "Queue-v1.json")),
            restoredSnapshot: FileQueueSnapshotStore.load(from: catalogURL.deletingLastPathComponent().appending(path: "Queue-v1.json")),
            learning: learning,
            automaticQueueProvider: recommendationQueue
        )
        return DefaultUMusicClient(
            authentication: authentication,
            playback: playback,
            library: library,
            playlists: playlists,
            personalization: learning,
            offline: offline,
            diagnostics: PlaceholderDiagnosticsProvider(),
            context: context,
            calendarPreferences: calendarPreferences
        )
    }
}
