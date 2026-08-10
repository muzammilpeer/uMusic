import Foundation
import Testing
import UMusicImportClient

@Test("HTTP is normalized, fragments are removed, and providers are classified")
func importURLPolicy() throws {
    let youtube = try ImportRequest(sourceURL: #require(URL(string: "http://YouTube.com/watch?v=abc#tracking")))
    #expect(youtube.sourceURL.absoluteString == "https://youtube.com/watch?v=abc")
    #expect(youtube.provider == .youtube)
    let mp3 = try ImportRequest(sourceURL: #require(URL(string: "https://media.example.invalid/music/one.MP3")))
    #expect(mp3.provider == .directMP3)
}

@Test("Malicious and unsupported URL forms are rejected")
func maliciousURLPolicy() throws {
    for value in ["file:///private/track.mp3", "javascript:alert(1)", "https://user:secret@example.com/a.mp3", "https://example.com/page"] {
        #expect(throws: (any Error).self) { try ImportRequest(sourceURL: #require(URL(string: value))) }
    }
    let longURL = try #require(URL(string: "https://example.invalid/" + String(repeating: "a", count: 2_100) + ".mp3"))
    #expect(throws: ImportRequestError.urlTooLong) { try ImportRequest(sourceURL: longURL) }
}

@Test("Multiple share representations choose the first supported normalized URL")
func representationSelection() throws {
    let values = [URL(fileURLWithPath: "/tmp/a"), try #require(URL(string: "http://youtu.be/abc")), try #require(URL(string: "https://example.com/b.mp3"))]
    #expect(try ImportURLPolicy.firstSupportedURL(in: values).absoluteString == "https://youtu.be/abc")
}

@Test("App Group handoff is idempotent and survives recreation")
func appGroupHandoff() async throws {
    let suite = "umusic-import-test-\(UUID())"
    UserDefaults.standard.removePersistentDomain(forName: suite)
    let handoff = try AppGroupImportHandoff(suiteName: suite)
    let request = try ImportRequest(sourceURL: #require(URL(string: "https://example.com/a.mp3")), idempotencyKey: UUID())
    #expect(try await handoff.enqueue(request))
    #expect(try await !handoff.enqueue(request))
    #expect(await (try AppGroupImportHandoff(suiteName: suite)).pending() == [request])
    try await handoff.remove(idempotencyKey: request.idempotencyKey)
    #expect(await handoff.pending().isEmpty)
}

@Test("Shared credential migration copies once without exposing fields")
func credentialMigration() async throws {
    let credentials = ImportCredentials(server: try #require(URL(string: "https://music.example")), accessToken: "test-token")
    let legacy = MemoryImportCredentialStore(credentials)
    let shared = MemoryImportCredentialStore()
    #expect(try await SharedCredentialMigration.migrateIfNeeded(from: legacy, to: shared))
    #expect(await shared.load() == credentials)
    #expect(try await !SharedCredentialMigration.migrateIfNeeded(from: legacy, to: shared))
}

@Test("Job deep links contain only the opaque job identifier")
func deepLink() {
    let id = UUID()
    let link = ImportDeepLink.job(id)
    #expect(link.absoluteString == "umusic://imports/jobs/\(id.uuidString.lowercased())")
    #expect(link.absoluteString.contains("token") == false)
}

private actor FailingImportClient: ImportJobSubmitting {
    func submit(_ request: ImportRequest, server: URL, token: String) async throws -> ImportJob { throw ImportClientError.offline }
    func status(jobID: UUID, server: URL, token: String) async throws -> ImportJob { throw ImportClientError.offline }
}

@Test("Offline submission preserves the App Group job for retry")
func offlineRetry() async throws {
    let suite = "umusic-import-offline-\(UUID())"
    let handoff = try AppGroupImportHandoff(suiteName: suite)
    let request = try ImportRequest(sourceURL: #require(URL(string: "https://example.com/retry.mp3")))
    try await handoff.enqueue(request)
    let credentials = MemoryImportCredentialStore(.init(server: try #require(URL(string: "https://music.example")), accessToken: "secret"))
    let processor = ImportHandoffProcessor(handoff: handoff, credentials: credentials, client: FailingImportClient())
    await #expect(throws: ImportClientError.offline) { try await processor.submitPending() }
    #expect(await handoff.pending() == [request])
}
