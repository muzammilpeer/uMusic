import Foundation
import UMusicDomain
import UMusicSupport

public enum TelemetryModule {
    public static let lowEnergyBatchSeconds = 120
}

/// Beta diagnostics deliberately records aggregate operational counters only. It has no
/// network dependency and cannot represent tracks, users, locations, health, or timelines.
public enum BetaDiagnosticMetric: String, CaseIterable, Codable, Sendable {
    case sessionStarted
    case sessionEndedNormally
    case playbackStartSucceeded
    case playbackStartFailed
    case playbackInterrupted
    case audioUnderrun
    case modelFallback
}

public struct BetaDiagnosticSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public let schemaVersion: Int
    public let frameworkVersion: String
    public let buildIdentifier: String
    public let counters: [String: Int]

    public init(frameworkVersion: String, buildIdentifier: String, counters: [String: Int]) {
        self.schemaVersion = Self.schemaVersion
        self.frameworkVersion = String(frameworkVersion.prefix(64))
        self.buildIdentifier = String(buildIdentifier.prefix(64))
        self.counters = counters
    }
}

public enum BetaDiagnosticsError: Error, Equatable, Sendable {
    case consentRequired
    case corruptStore
}

public actor BetaDiagnosticsBuffer {
    private struct StoredDocument: Codable {
        var schemaVersion = BetaDiagnosticSnapshot.schemaVersion
        var optedIn = false
        var counters: [String: Int] = [:]
    }

    private let url: URL
    private let frameworkVersion: String
    private let buildIdentifier: String
    private var document: StoredDocument

    public init(url: URL, frameworkVersion: String, buildIdentifier: String) {
        self.url = url
        self.frameworkVersion = frameworkVersion
        self.buildIdentifier = buildIdentifier
        if let data = try? Data(contentsOf: url),
           let value = try? JSONDecoder().decode(StoredDocument.self, from: data),
           value.schemaVersion == BetaDiagnosticSnapshot.schemaVersion {
            document = value
        } else {
            document = StoredDocument()
        }
    }

    public func setOptedIn(_ optedIn: Bool) throws {
        document.optedIn = optedIn
        if !optedIn { document.counters.removeAll() }
        try persist()
    }

    public func isOptedIn() -> Bool { document.optedIn }

    public func record(_ metric: BetaDiagnosticMetric, count: Int = 1) throws {
        guard document.optedIn else { return }
        guard count > 0 else { return }
        let current = document.counters[metric.rawValue, default: 0]
        let remaining = max(1_000_000_000 - current, 0)
        document.counters[metric.rawValue] = current + min(count, remaining)
        try persist()
    }

    /// Returns a user-initiated, aggregate-only payload. Callers may present it in a
    /// share sheet; this component never uploads it.
    public func exportSnapshot() throws -> BetaDiagnosticSnapshot {
        guard document.optedIn else { throw BetaDiagnosticsError.consentRequired }
        return BetaDiagnosticSnapshot(
            frameworkVersion: frameworkVersion,
            buildIdentifier: buildIdentifier,
            counters: document.counters
        )
    }

    public func reset() throws {
        document.counters.removeAll()
        try persist()
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try JSONEncoder().encode(document).write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
