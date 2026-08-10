import Foundation
import Testing
import UMusicCore
import UMusicSupport

@Test("The placeholder composition root exposes every capability")
func compositionRootIsComplete() async throws {
    let client = UMusicCompositionRoot.makePlaceholderClient()
    let authentication = await client.authentication.snapshots.first { _ in true }
    let playback = await client.playback.snapshots.first { _ in true }
    let library = await client.library.snapshots.first { _ in true }

    #expect(authentication == .signedOut)
    #expect(playback == .idle)
    #expect(library == .empty)
    #expect(try await client.playlists.playlists().isEmpty)
    #expect(await client.offline.storageSnapshot().quotaBytes == 500 * 1_024 * 1_024)
    #expect(await client.diagnostics.snapshot().frameworkVersion == UMusicCoreVersion.current)
}

@Test("The framework resource manifest matches its public version")
func resourceManifestMatchesVersion() throws {
    let manifest = try UMusicResources.manifest()
    #expect(manifest.frameworkVersion == UMusicCoreVersion.current)
    #expect(manifest.schemaVersion == 1)
}

@Test("Seeded randomness is reproducible")
func seededRandomIsDeterministic() async {
    let first = SeededRandomProvider(seed: 42)
    let second = SeededRandomProvider(seed: 42)

    for _ in 0..<20 {
        #expect(await first.nextUnitInterval() == second.nextUnitInterval())
    }
}

@Test("Sensitive log fields are redacted before reaching the system logger")
func loggerRedactsSensitiveFields() {
    let logger = RedactedLogger(category: "tests")
    let rendered = logger.render(
        "request_failed",
        fields: [
            LogField("request_id", "safe-id", privacy: .safe),
            LogField("token", "secret-token", privacy: .sensitive),
        ]
    )

    #expect(rendered.contains("request_id=safe-id"))
    #expect(rendered.contains("token=<redacted>"))
    #expect(!rendered.contains("secret-token"))
}
