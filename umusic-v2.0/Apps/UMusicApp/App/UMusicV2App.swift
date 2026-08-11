import SwiftUI
import UMusicCore
import UMusicOffline
import UMusicImportClient
import UMusicPresentation
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit

private final class BackgroundCompletionBox: @unchecked Sendable {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
}

final class UMusicAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        let completion = BackgroundCompletionBox(completionHandler)
        BackgroundDownloadCompletionRegistry.shared.register(identifier: identifier) { Task { @MainActor in completion.handler() } }
    }
}
#endif

@main
struct UMusicV2App: App {
#if os(iOS)
    @UIApplicationDelegateAdaptor(UMusicAppDelegate.self) private var appDelegate
#endif
    @Environment(\.scenePhase) private var scenePhase
    private let client = UMusicCompositionRoot.makeLiveClient()

    var body: some Scene {
        WindowGroup {
            UMusicRootView(client: client)
                .task { await processSharedImports() }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { Task { await client.playback.checkpoint() } }
                    if phase == .active { Task { await processSharedImports() } }
                }
        }
        .commands {
            UMusicCommandMenus()
#if os(macOS)
            InspectorCommands()
#endif
        }
    }

    private func processSharedImports() async {
        do {
            guard let importAccessGroup = Bundle.main.object(forInfoDictionaryKey: "UMusicSharedKeychainAccessGroup") as? String,
                  !importAccessGroup.isEmpty else { return }
            let serverConfiguration = try await client.authentication.currentServer()
            let server = serverConfiguration.baseURL
            let token = try await client.authentication.validAccessToken()
            let credentials = SharedKeychainImportCredentialStore(accessGroup: importAccessGroup)
            try await credentials.save(.init(server: server, accessToken: token))
            let handoff = try AppGroupImportHandoff(suiteName: "group.uk.muzammilpeer.umusic")
            _ = try await ImportHandoffProcessor(handoff: handoff, credentials: credentials, client: URLSessionImportJobClient()).submitPending()
        } catch {
            // Pending jobs remain in the App Group for the next foreground retry.
        }
    }
}

#if os(macOS)
private struct InspectorCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Open uMusic Data Inspector") {
                let sibling = Bundle.main.bundleURL.deletingLastPathComponent().appending(path: "UMusicDataInspector.app")
                let installed = URL(fileURLWithPath: "/Applications/UMusicDataInspector.app")
                if let target = [sibling, installed].first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                    NSWorkspace.shared.openApplication(at: target, configuration: .init())
                }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
#endif
