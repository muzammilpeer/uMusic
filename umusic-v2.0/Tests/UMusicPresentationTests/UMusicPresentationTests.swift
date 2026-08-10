import Foundation
import Testing
import UMusicCore
@testable import UMusicPresentation

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

@Test("Home mix construction stays bounded for a large cached library")
func homeMixPerformance() {
    let tracks = (0..<25_000).map { index in
        TrackSummary(id: UUID(), title: "Song \(index)", artist: "Artist", genres: [index.isMultiple(of: 2) ? "Rock" : "Jazz"], releaseYear: 1980 + index % 45)
    }
    let clock = ContinuousClock()
    let elapsed = clock.measure { _ = HomeStarterMix.make(from: tracks) }
    #expect(elapsed < .seconds(2))
}

@Test("Home keeps privacy, offline launch, and mini-player layout contracts")
func homeSourceContracts() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let home = try String(contentsOf: root.appending(path: "Sources/UMusicPresentation/Screens/HomeScreen.swift"), encoding: .utf8)
    let shell = try String(contentsOf: root.appending(path: "Sources/UMusicPresentation/AppShellView.swift"), encoding: .utf8)
    #expect(!home.contains(".sync()"))
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
