import Foundation
import Testing
import UMusicTelemetry

@Test("Beta diagnostics are off by default and opting out erases aggregates")
func betaDiagnosticsConsentLifecycle() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appending(path: "beta-diagnostics-v1.json")
    let buffer = BetaDiagnosticsBuffer(url: url, frameworkVersion: "2.0.0", buildIdentifier: "19")

    try await buffer.record(.playbackStartSucceeded)
    await #expect(throws: BetaDiagnosticsError.consentRequired) { try await buffer.exportSnapshot() }
    try await buffer.setOptedIn(true)
    try await buffer.record(.playbackStartSucceeded, count: 3)
    try await buffer.record(.playbackStartFailed)
    let snapshot = try await buffer.exportSnapshot()
    #expect(snapshot.counters == ["playbackStartSucceeded": 3, "playbackStartFailed": 1])

    try await buffer.setOptedIn(false)
    try await buffer.setOptedIn(true)
    #expect(try await buffer.exportSnapshot().counters.isEmpty)
}

@Test("Beta payload is aggregate-only, bounded, protected, and survives relaunch")
func betaDiagnosticsPayloadContract() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appending(path: "beta-diagnostics-v1.json")
    let buffer = BetaDiagnosticsBuffer(url: url, frameworkVersion: String(repeating: "v", count: 100), buildIdentifier: String(repeating: "b", count: 100))
    try await buffer.setOptedIn(true)
    try await buffer.record(.audioUnderrun, count: Int.max)

    let restored = BetaDiagnosticsBuffer(url: url, frameworkVersion: "2.0.0", buildIdentifier: "19")
    let snapshot = try await restored.exportSnapshot()
    #expect(snapshot.counters["audioUnderrun"] == 1_000_000_000)
    let encoded = try JSONEncoder().encode(snapshot)
    let text = String(decoding: encoded, as: UTF8.self).lowercased()
    for forbidden in ["track", "song", "location", "latitude", "health", "timeline", "timestamp", "username", "token", "url", "path"] {
        #expect(!text.contains(forbidden))
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}
