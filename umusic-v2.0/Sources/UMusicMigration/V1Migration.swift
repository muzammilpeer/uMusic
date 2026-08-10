import CryptoKit
import Foundation
import UMusicDomain

public enum V1MigrationFile: String, CaseIterable, Sendable {
    case catalog = "catalog.json"
    case queue = "queue.json"
    case history = "pending-events.json"
    case settings = "settings.json"
}

public protocol V1MigrationSource: Sendable { func read(_ file: V1MigrationFile) async throws -> Data? }

public struct DirectoryV1MigrationSource: V1MigrationSource {
    private let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL }
    public func read(_ file: V1MigrationFile) async throws -> Data? {
        let url = root.appending(path: file.rawValue).standardizedFileURL
        guard url.deletingLastPathComponent() == root else { throw V1MigrationError.invalidSource }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
}

public struct V1Track: Codable, Equatable, Sendable {
    public struct Artist: Codable, Equatable, Sendable { public let id: UUID; public let name: String; public init(id: UUID, name: String) { self.id = id; self.name = name } }
    public struct Album: Codable, Equatable, Sendable { public let id: UUID; public let title: String; public init(id: UUID, title: String) { self.id = id; self.title = title } }
    public let id: UUID; public let title: String; public let artist: Artist; public let album: Album?
    public let durationMS: Int64; public let genres: [String]; public let energy: Double?; public let streamPath: String?
    public init(id: UUID, title: String, artist: Artist, album: Album? = nil, durationMS: Int64, genres: [String] = [], energy: Double? = nil, streamPath: String? = nil) { self.id = id; self.title = title; self.artist = artist; self.album = album; self.durationMS = durationMS; self.genres = genres; self.energy = energy; self.streamPath = streamPath }
    enum CodingKeys: String, CodingKey { case id, title, artist, album, genres, energy; case durationMS = "duration_ms"; case streamPath = "stream_path" }
}

public struct V1ListeningEvent: Codable, Equatable, Sendable {
    public let clientEventID: UUID; public let playbackID: UUID; public let trackID: UUID; public let eventType: String; public let clientTimestamp: Date; public let positionMS: Int64; public let durationMS: Int64; public let listenedMSDelta: Int64; public let offline: Bool
    public init(clientEventID: UUID, playbackID: UUID, trackID: UUID, eventType: String, clientTimestamp: Date, positionMS: Int64, durationMS: Int64, listenedMSDelta: Int64, offline: Bool) { self.clientEventID = clientEventID; self.playbackID = playbackID; self.trackID = trackID; self.eventType = eventType; self.clientTimestamp = clientTimestamp; self.positionMS = positionMS; self.durationMS = durationMS; self.listenedMSDelta = listenedMSDelta; self.offline = offline }
    enum CodingKeys: String, CodingKey { case clientEventID = "client_event_id", playbackID = "playback_id", trackID = "track_id", eventType = "event_type", clientTimestamp = "client_timestamp", positionMS = "position_ms", durationMS = "duration_ms", listenedMSDelta = "listened_ms_delta", offline }
}

public struct V1Settings: Codable, Equatable, Sendable {
    public let lowEnergyMode: Bool?; public let wifiOnly: Bool?; public let chargingOnly: Bool?; public let quotaBytes: Int64?
    public init(lowEnergyMode: Bool? = nil, wifiOnly: Bool? = nil, chargingOnly: Bool? = nil, quotaBytes: Int64? = nil) { self.lowEnergyMode = lowEnergyMode; self.wifiOnly = wifiOnly; self.chargingOnly = chargingOnly; self.quotaBytes = quotaBytes }
}

public struct MigrationManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int; public let migrationID: UUID; public let state: String
    public let sourceChecksums: [String: String]; public let outputChecksums: [String: String]
    public let counts: [String: Int]; public let identityMappings: [String: String]; public let unsupportedFields: [String]
}
public struct MigrationResult: Equatable, Sendable { public let packageURL: URL; public let manifest: MigrationManifest }
public enum V1MigrationError: Error, Equatable, Sendable { case invalidSource, corruptSource(String), sourceChanged, insufficientDisk, interrupted, outputValidationFailed, confirmationRequired, completedMigrationCannotRollback }

public actor V1MigrationAdapter {
    public static let unsupportedFields = ["credentials", "server_url", "device_id", "stream_url", "stream_path", "cached_media_bytes", "raw_route", "healthkit_raw"]
    private let manager = FileManager.default
    public init() {}

    public func migrate(source: any V1MigrationSource, destinationRoot: URL, migrationID: UUID, availableCapacityBytes: Int64? = nil, interruptAfterPhase: Int? = nil) async throws -> MigrationResult {
        let root = destinationRoot.standardizedFileURL
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let available = availableCapacityBytes ?? ((try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? Int64.max)
        guard available >= 2_000_000 else { throw V1MigrationError.insufficientDisk }
        let staging = root.appending(path: "migration-\(migrationID.uuidString.lowercased()).staging", directoryHint: .isDirectory)
        let ready = root.appending(path: "migration-\(migrationID.uuidString.lowercased()).ready", directoryHint: .isDirectory)
        if manager.fileExists(atPath: ready.path) { return try result(at: ready) }
        try manager.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let sourceData = try await loadSource(source)
        var checkpoint = try loadCheckpoint(at: staging) ?? Checkpoint(migrationID: migrationID, sourceChecksums: sourceData.checksums, completed: [])
        guard checkpoint.migrationID == migrationID, checkpoint.sourceChecksums == sourceData.checksums else { throw V1MigrationError.sourceChanged }
        let phases = try outputs(from: sourceData)
        for (index, phase) in phases.enumerated() where !checkpoint.completed.contains(phase.0) {
            try protectedWrite(phase.1, to: staging.appending(path: phase.0))
            checkpoint.completed.append(phase.0); try saveCheckpoint(checkpoint, at: staging)
            if interruptAfterPhase == index + 1 { throw V1MigrationError.interrupted }
        }
        let manifest = try makeManifest(migrationID: migrationID, source: sourceData, staging: staging)
        try protectedWrite(try encoder.encode(manifest), to: staging.appending(path: "manifest.json"))
        try validate(package: staging, manifest: manifest)
        try manager.moveItem(at: staging, to: ready)
        return .init(packageURL: ready, manifest: manifest)
    }

    public func rollbackIncomplete(migrationID: UUID, destinationRoot: URL, confirmed: Bool) throws {
        guard confirmed else { throw V1MigrationError.confirmationRequired }
        let root = destinationRoot.standardizedFileURL
        let staging = root.appending(path: "migration-\(migrationID.uuidString.lowercased()).staging", directoryHint: .isDirectory).standardizedFileURL
        let ready = root.appending(path: "migration-\(migrationID.uuidString.lowercased()).ready", directoryHint: .isDirectory)
        guard staging.deletingLastPathComponent() == root else { throw V1MigrationError.invalidSource }
        if manager.fileExists(atPath: ready.path) { throw V1MigrationError.completedMigrationCannotRollback }
        try? manager.removeItem(at: staging)
    }

    private struct SourceData { let values: [V1MigrationFile: Data]; let checksums: [String: String] }
    private struct Checkpoint: Codable { let migrationID: UUID; let sourceChecksums: [String: String]; var completed: [String] }
    private func loadSource(_ source: any V1MigrationSource) async throws -> SourceData {
        var values: [V1MigrationFile: Data] = [:], checksums: [String: String] = [:]
        for file in V1MigrationFile.allCases {
            if let data = try await source.read(file) { guard data.count <= 256_000_000 else { throw V1MigrationError.corruptSource(file.rawValue) }; values[file] = data; checksums[file.rawValue] = sha256(data) }
        }
        guard !values.isEmpty else { throw V1MigrationError.invalidSource }
        return .init(values: values, checksums: checksums)
    }
    private func outputs(from source: SourceData) throws -> [(String, Data)] {
        var result: [(String, Data)] = []
        if let data = source.values[.catalog] { let values = try decode([V1Track].self, data, file: .catalog).map(summary); result.append(("catalog-v2.json", try encoder.encode(values))) }
        if let data = source.values[.queue] { let values = try decode([V1Track].self, data, file: .queue).map(summary); result.append(("queue-v2.json", try encoder.encode(values))) }
        if let data = source.values[.history] { result.append(("history-v2.json", try encoder.encode(try decode([V1ListeningEvent].self, data, file: .history)))) }
        if let data = source.values[.settings] { result.append(("settings-v2.json", try encoder.encode(try decode(V1Settings.self, data, file: .settings)))) }
        return result
    }
    private func summary(_ value: V1Track) -> TrackSummary { .init(id: value.id, title: value.title, artist: value.artist.name, durationSeconds: Double(max(value.durationMS, 0)) / 1_000, album: value.album?.title, genres: value.genres) }
    private func makeManifest(migrationID: UUID, source: SourceData, staging: URL) throws -> MigrationManifest {
        let outputs = try manager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasSuffix("-v2.json") }
        var outputChecksums: [String: String] = [:], counts: [String: Int] = [:], mappings: [String: String] = [:]
        for url in outputs { outputChecksums[url.lastPathComponent] = sha256(try Data(contentsOf: url)) }
        if let data = source.values[.catalog] { let values = try decode([V1Track].self, data, file: .catalog); counts["tracks"] = values.count; for value in values { mappings["track:\(value.id.uuidString.lowercased())"] = value.id.uuidString.lowercased() } }
        if let data = source.values[.queue] { counts["queue_items"] = try decode([V1Track].self, data, file: .queue).count }
        if let data = source.values[.history] { counts["history_events"] = try decode([V1ListeningEvent].self, data, file: .history).count }
        return .init(schemaVersion: 1, migrationID: migrationID, state: "ready", sourceChecksums: source.checksums, outputChecksums: outputChecksums, counts: counts, identityMappings: mappings, unsupportedFields: Self.unsupportedFields)
    }
    private func validate(package: URL, manifest: MigrationManifest) throws { for (name, expected) in manifest.outputChecksums { guard let data = try? Data(contentsOf: package.appending(path: name)), sha256(data) == expected else { throw V1MigrationError.outputValidationFailed } } }
    private func result(at package: URL) throws -> MigrationResult { let manifest = try decoder.decode(MigrationManifest.self, from: Data(contentsOf: package.appending(path: "manifest.json"))); try validate(package: package, manifest: manifest); return .init(packageURL: package, manifest: manifest) }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data, file: V1MigrationFile) throws -> T { do { return try decoder.decode(type, from: data) } catch { throw V1MigrationError.corruptSource(file.rawValue) } }
    private func loadCheckpoint(at root: URL) throws -> Checkpoint? { let url = root.appending(path: "checkpoint.json"); guard manager.fileExists(atPath: url.path) else { return nil }; do { return try decoder.decode(Checkpoint.self, from: Data(contentsOf: url)) } catch { throw V1MigrationError.outputValidationFailed } }
    private func saveCheckpoint(_ value: Checkpoint, at root: URL) throws { try protectedWrite(try encoder.encode(value), to: root.appending(path: "checkpoint.json")) }
    private func protectedWrite(_ data: Data, to url: URL) throws { try data.write(to: url, options: [.atomic, .completeFileProtection]); try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
    private func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private var encoder: JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; value.outputFormatting = [.sortedKeys]; return value }
    private var decoder: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
}
