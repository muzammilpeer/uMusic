import SwiftUI

@main
struct UMusicApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: SessionStore
    @StateObject private var player = AudioPlayer()

    init() {
        let api = APIClient()
        _session = StateObject(wrappedValue: SessionStore(api: api))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if session.token == nil { OnboardingView() }
                else { LibraryView(api: session.api) }
            }
            .uMusicTextInputBehavior()
            .environmentObject(session)
            .environmentObject(player)
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { player.persistPlaybackState() }
            }
        }
        #if os(macOS)
        .commands {
            CommandMenu("Playback") {
                Button(player.isPlaying ? "Pause" : "Play") { player.toggle() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Next Track") { player.next() }.keyboardShortcut(.rightArrow)
                Button("Previous Track") { player.previous() }.keyboardShortcut(.leftArrow)
            }
        }
        #endif
    }
}
