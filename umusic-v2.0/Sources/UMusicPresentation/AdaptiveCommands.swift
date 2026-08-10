import SwiftUI

extension AppTab {
    var title: LocalizedStringKey {
        switch self { case .home: return "Home"; case .library: return "Library"; case .now: return "Now Playing"; case .search: return "Search" }
    }
    var systemImage: String {
        switch self { case .home: return "house"; case .library: return "music.note.list"; case .now: return "play.circle"; case .search: return "magnifyingglass" }
    }
}

public struct UMusicCommandActions {
    let selectTab: (AppTab) -> Void
    let togglePlayback: () -> Void
    public init(selectTab: @escaping (AppTab) -> Void, togglePlayback: @escaping () -> Void) {
        self.selectTab = selectTab; self.togglePlayback = togglePlayback
    }
}

private struct UMusicCommandKey: FocusedValueKey { typealias Value = UMusicCommandActions }

extension FocusedValues {
    var uMusicCommands: UMusicCommandActions? {
        get { self[UMusicCommandKey.self] }
        set { self[UMusicCommandKey.self] = newValue }
    }
}

public struct UMusicCommandMenus: Commands {
    @FocusedValue(\.uMusicCommands) private var actions
    public init() {}
    public var body: some Commands {
        CommandMenu("uMusic") {
            Button("Home") { actions?.selectTab(.home) }.keyboardShortcut("1", modifiers: .command)
            Button("Library") { actions?.selectTab(.library) }.keyboardShortcut("2", modifiers: .command)
            Button("Now Playing") { actions?.selectTab(.now) }.keyboardShortcut("3", modifiers: .command)
            Button("Search") { actions?.selectTab(.search) }.keyboardShortcut("f", modifiers: .command)
            Divider()
            Button("Play or Pause") { actions?.togglePlayback() }.keyboardShortcut(.space, modifiers: [])
        }
    }
}
