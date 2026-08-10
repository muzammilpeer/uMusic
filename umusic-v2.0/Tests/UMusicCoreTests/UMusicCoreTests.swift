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

@Test("Beta release freeze pins every persisted and exported schema")
func betaReleaseFreeze() throws {
    let freeze = try UMusicResources.releaseFreezeManifest()
    #expect(freeze.releaseTrain == "2.0.0-beta.1")
    #expect(freeze.frameworkVersion == UMusicCoreVersion.current)
    #expect(freeze.publicAPIBaseline == 1)
    #expect(freeze.status == "frozen-for-beta-validation")
    #expect(freeze.schemas == [
        "catalog": 1, "context": 1, "learning": 1, "migration_package": 1,
        "model_manifest": 1, "offline_index": 1, "queue_snapshot": 1,
        "research_export": 1, "beta_diagnostics": 1,
    ])
}

@Test("Diagnostics remove sensitive metadata and expose stable local versions")
func diagnosticsRedaction() async {
    let issue = DiagnosticIssue(code: "SYNC_FAILED", metadata: ["retry": "yes", "server_url": "https://secret", "file_path": "/private/data", "health_value": "190"])
    #expect(issue.metadata == ["retry": "yes"])
    let snapshot = await LocalDiagnosticsProvider(buildIdentifier: "42").snapshot()
    #expect(snapshot.frameworkVersion == UMusicCoreVersion.current)
    #expect(snapshot.buildIdentifier == "42")
    #expect(snapshot.issues.allSatisfy { $0.code.uppercased() == $0.code })
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

@Test("Privacy manifest declares every required-reason API used by v2")
func privacyManifestReasons() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appending(path: "Sources/UMusicCore/Resources/PrivacyInfo.xcprivacy"))
    let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    let entries = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
    let reasons = Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (String, Set<String>)? in
        guard let type = entry["NSPrivacyAccessedAPIType"] as? String, let values = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] else { return nil }
        return (type, Set(values))
    })
    #expect(reasons["NSPrivacyAccessedAPICategoryUserDefaults"] == Set(["CA92.1", "1C8F.1"]))
    #expect(reasons["NSPrivacyAccessedAPICategoryDiskSpace"] == Set(["E174.1"]))
    #expect(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"] == Set(["C617.1"]))
    #expect(plist["NSPrivacyTracking"] as? Bool == false)
}

@Test("Catalog persistence requests WAL, indexes, batching, and file protection")
func catalogHardeningSourceContract() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appending(path: "Sources/UMusicData/CatalogStore.swift"), encoding: .utf8)
    #expect(source.contains("journal_mode\": \"WAL"))
    #expect(source.contains("fetchBatchSize = 500"))
    #expect(source.contains("NSPersistentStoreFileProtectionKey"))
    #expect(source.contains("\"releaseYear\", \"available\""))
}
