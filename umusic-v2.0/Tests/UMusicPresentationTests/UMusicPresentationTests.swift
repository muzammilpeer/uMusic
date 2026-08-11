import Foundation
import Testing
import UMusicCore
@testable import UMusicPresentation

private actor RestoringAuthenticationStub: AuthenticationManaging {
    nonisolated let snapshots: AsyncStream<AuthenticationState>
    private let continuation: AsyncStream<AuthenticationState>.Continuation
    private let user = AuthenticatedUser(id: UUID(), displayName: "Listener")
    private let server = ServerConfiguration(baseURL: URL(string: "https://music.example")!)

    init() {
        let stream = AsyncStream<AuthenticationState>.makeStream()
        snapshots = stream.stream
        continuation = stream.continuation
        continuation.yield(.signedOut)
    }

    func restore() async {
        continuation.yield(.authenticated(user: user, server: server, persistsSession: true))
        continuation.finish()
    }
    func connect(serverURL: String, username: String, password: String, keepSignedIn: Bool, allowsInsecureLocalhost: Bool) async {}
    func validAccessToken() async throws -> String { "token" }
    func currentServer() async throws -> ServerConfiguration { server }
    func logout(localData: LogoutLocalDataDisposition) async {}
}

@MainActor
@Test("Persisted authentication stays behind launch loading until restoration resolves")
func restoredAuthenticationDoesNotExposeSignedOutUI() async {
    let model = AuthenticationViewModel(authentication: RestoringAuthenticationStub())
    #expect(model.isRestoringSession)

    await model.observe()

    #expect(!model.isRestoringSession)
    guard case .authenticated = model.state else {
        Issue.record("Expected the restored authenticated state")
        return
    }
}

@MainActor
@Test("Each tab keeps an independent typed navigation history")
func independentNavigationPaths() {
    let model = AppNavigationModel()
    let trackID = UUID()
    let playlistID = UUID()

    model.homePath.append(.track(trackID))
    model.libraryPath.append(.playlist(playlistID))
    model.selectedTab = .library

    #expect(model.homePath == [.track(trackID)])
    #expect(model.libraryPath == [.playlist(playlistID)])
    #expect(model.nowPath.isEmpty)
    #expect(model.searchPath.isEmpty)
    #expect(model.selectedTab == .library)
}

@MainActor @Test("Window restoration preserves typed routes and bounds untrusted state")
func windowRestoration() {
    let source = AppNavigationModel(), track = UUID(), playlist = UUID()
    source.selectedTab = .library; source.homePath = [.track(track)]; source.libraryPath = [.playlist(playlist)]; source.searchQuery = String(repeating: "q", count: 700)
    let restored = AppNavigationModel(); restored.restore(from: source.restorationData())
    #expect(restored.selectedTab == .library)
    #expect(restored.homePath == [.track(track)])
    #expect(restored.libraryPath == [.playlist(playlist)])
    #expect(restored.searchQuery.count == 512)
    let unchanged = restored.selectedTab
    restored.restore(from: Data(repeating: 0, count: 65_537))
    #expect(restored.selectedTab == unchanged)
}

@Test("The shell exposes exactly the four planned primary tabs")
func primaryTabsAreStable() {
    #expect(AppTab.allCases == [.home, .library, .now, .search])
}

@MainActor @Test("Deep links route stable tracks, playlists, and searches")
func deepLinkRouting() {
    let model = AppNavigationModel()
    let track = UUID(), playlist = UUID()
    #expect(model.open(URL(string: "umusic://track/\(track)")!))
    #expect(model.selectedTab == .library)
    #expect(model.libraryPath.last == .track(track))
    #expect(model.open(URL(string: "umusic://playlist/\(playlist)")!))
    #expect(model.libraryPath.last == .playlist(playlist))
    #expect(model.open(URL(string: "umusic://search?q=deep%20focus")!))
    #expect(model.selectedTab == .search)
    #expect(model.searchQuery == "deep focus")
    #expect(!model.open(URL(string: "https://example.com/track/\(track)")!))
}

@Test("Library surfaces retain accessibility and keyboard-safe behavior")
func libraryAccessibilityContract() throws {
    let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "Sources/UMusicPresentation/Screens/LibraryViews.swift"), encoding: .utf8)
    #expect(source.contains(".accessibilityLabel"))
    #expect(source.contains(".accessibilityElement"))
    #expect(source.contains(".scrollDismissesKeyboard(.interactively)"))
    #expect(!source.contains(".font(.system(size:"))
}

@Test("Theme preferences are stable and invalid persisted values fall back cleanly")
func appearancePreferenceContract() {
    #expect(UMusicThemePreference.allCases.map(\.rawValue) == ["system", "light", "dark"])
    #expect(UMusicAccent.allCases.map(\.rawValue) == ["violet", "blue", "orange", "green"])
    #expect(UMusicThemePreference(rawValue: "invalid") == nil)
}

@Test("Appearance values persist through UserDefaults relaunch semantics")
func appearancePersistence() throws {
    let suite = "UMusicPresentationTests.Appearance.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(UMusicThemePreference.dark.rawValue, forKey: UMusicTheme.themeDefaultsKey)
    defaults.set(UMusicAccent.blue.rawValue, forKey: UMusicTheme.accentDefaultsKey)
    let relaunched = try #require(UserDefaults(suiteName: suite))
    #expect(UMusicThemePreference(rawValue: relaunched.string(forKey: UMusicTheme.themeDefaultsKey) ?? "") == .dark)
    #expect(UMusicAccent(rawValue: relaunched.string(forKey: UMusicTheme.accentDefaultsKey) ?? "") == .blue)
}

@Test("Home starter mixes remain useful before learned history exists")
func coldStartMixes() {
    let rock = TrackSummary(id: UUID(), title: "One", artist: "Artist", genres: ["Rock"], releaseYear: 1999)
    let unknown = TrackSummary(id: UUID(), title: "Two", artist: "Artist")
    let mixes = HomeStarterMix.make(from: [rock, unknown])
    #expect(mixes.first?.id == "all")
    #expect(mixes.contains { $0.title == "Rock" })
    #expect(mixes.contains { $0.id == "recent-era" })
    #expect(HomeStarterMix.make(from: []).isEmpty)
}

@Test("Reduce Motion disables Home transition animation")
func homeReduceMotionContract() {
    #expect(HomeMotionPolicy.animation(reduceMotion: true) == nil)
    #expect(HomeMotionPolicy.animation(reduceMotion: false) != nil)
}

@Test("Visualizer throttles for energy and stops for accessibility or background")
func visualizerPolicyContract() {
    #expect(VisualizerPolicy.framesPerSecond(isPlaying: true, isVisible: true, sceneActive: true, reduceMotion: false, lowEnergyMode: false) == 15)
    #expect(VisualizerPolicy.framesPerSecond(isPlaying: true, isVisible: true, sceneActive: true, reduceMotion: false, lowEnergyMode: true) == 4)
    #expect(VisualizerPolicy.framesPerSecond(isPlaying: true, isVisible: true, sceneActive: true, reduceMotion: true, lowEnergyMode: false) == 0)
    #expect(VisualizerPolicy.framesPerSecond(isPlaying: true, isVisible: true, sceneActive: false, reduceMotion: false, lowEnergyMode: false) == 0)
    #expect(VisualizerPolicy.bars(position: 2).allSatisfy { (0.1...0.9).contains($0) })
}

@Test("Visualizer never captures microphone or installs an audio engine")
func visualizerSourceIsolation() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appending(path: "Sources/UMusicPresentation/VisualizerView.swift"), encoding: .utf8)
    #expect(!source.contains("AVAudioEngine"))
    #expect(!source.contains("AVAudioRecorder"))
    #expect(!source.localizedCaseInsensitiveContains("microphone"))
}

@Test("Home mix construction stays bounded for a large cached library")
func homeMixPerformance() {
    let tracks = (0..<25_000).map { index in
        TrackSummary(id: UUID(), title: "Song \(index)", artist: "Artist", genres: [index.isMultiple(of: 2) ? "Rock" : "Jazz"], releaseYear: 1980 + index % 45)
    }
    let clock = ContinuousClock()
    var mixes: [HomeStarterMix] = []
    let elapsed = clock.measure { mixes = HomeStarterMix.make(from: tracks) }
    #expect(elapsed < .seconds(2))
    #expect(mixes.first?.title == "All Music")
    #expect(mixes.first?.tracks.count == tracks.count)
}

@Test("Home keeps privacy, offline launch, and mini-player layout contracts")
func homeSourceContracts() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let home = try String(contentsOf: root.appending(path: "Sources/UMusicPresentation/Screens/HomeScreen.swift"), encoding: .utf8)
    let shell = try String(contentsOf: root.appending(path: "Sources/UMusicPresentation/AppShellView.swift"), encoding: .utf8)
    #expect(home.contains(".refreshable"))
    #expect(!home.localizedCaseInsensitiveContains("latitude"))
    #expect(!home.localizedCaseInsensitiveContains("longitude"))
    #expect(home.contains("LazyVStack"))
    #expect(shell.contains(".safeAreaInset(edge: .bottom"))
}

@Test("Context UI requires explicit actions and keeps unsupported macOS sensors out")
func contextUISourceContract() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let shell = try String(contentsOf: root.appending(path: "Sources/UMusicPresentation/AppShellView.swift"), encoding: .utf8)
    #expect(shell.contains("Start Activity Context"))
    #expect(shell.contains("Sample Activity Now"))
    #expect(shell.contains("#if os(iOS)"))
    #expect(!shell.localizedCaseInsensitiveContains("airpods battery"))
    #expect(!shell.contains("Timer.publish"))
}

@Test("Adaptive shell provides sidebar, restoration, keyboard focus, and semantic layout")
func adaptiveShellSourceContract() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let shell = try String(contentsOf: root.appending(path: "Sources/UMusicPresentation/AppShellView.swift"), encoding: .utf8)
    let commands = try String(contentsOf: root.appending(path: "Sources/UMusicPresentation/AdaptiveCommands.swift"), encoding: .utf8)
    #expect(shell.contains("NavigationSplitView"))
    #expect(shell.contains("@SceneStorage"))
    #expect(shell.contains("horizontalSizeClass == .regular"))
    #expect(shell.contains("focusedSceneValue"))
    #expect(commands.contains("keyboardShortcut"))
    #expect(!shell.contains("layoutDirection =="))
}

@Test("macOS does not invent an audio route")
func macAudioRouteSourceContract() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appending(path: "Sources/UMusicContext/SystemPassiveContextProviders.swift"), encoding: .utf8)
    #expect(source.contains("#else\n        return .unknown"))
}
