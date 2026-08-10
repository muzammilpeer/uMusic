import CryptoKit
import Foundation

public enum ReleaseBackupStore: String, CaseIterable, Codable, Sendable {
    case catalog = "Catalog.sqlite"
    case catalogWAL = "Catalog.sqlite-wal"
    case catalogSHM = "Catalog.sqlite-shm"
    case learning = "Learning-v1.json"
    case playlists = "Playlists-v1.json"
    case queue = "Queue-v1.json"
    case offlineIndex = "Offline/index-v1.json"
}

public struct ReleaseBackupManifest: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public let schemaVersion: Int
    public let files: [String: String]
    public let byteCounts: [String: Int64]

    public init(files: [String: String], byteCounts: [String: Int64]) {
        schemaVersion = Self.schemaVersion
        self.files = files
        self.byteCounts = byteCounts
    }
}

public enum ReleaseBackupError: Error, Equatable, Sendable {
    case noStores
    case invalidArchive
    case destinationNotEmpty
}

/// Creates and restores fixed-name snapshots. The caller must quiesce stores before
/// backup; SQLite's database, WAL, and SHM files are treated as one snapshot set.
public actor ReleaseBackupCoordinator {
    private let manager = FileManager.default
    public init() {}

    public func createSnapshot(from storeRoot: URL, at archiveRoot: URL) throws -> ReleaseBackupManifest {
        let source = storeRoot.standardizedFileURL
        let archive = archiveRoot.standardizedFileURL
        guard source != archive else { throw ReleaseBackupError.invalidArchive }
        let staging = archive.appendingPathExtension("staging")
        try? manager.removeItem(at: staging)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        do {
            var hashes: [String: String] = [:]
            var counts: [String: Int64] = [:]
            for store in ReleaseBackupStore.allCases {
                let input = source.appending(path: store.rawValue)
                guard manager.fileExists(atPath: input.path) else { continue }
                let output = staging.appending(path: store.rawValue)
                try manager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.copyItem(at: input, to: output)
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
                hashes[store.rawValue] = try checksum(output)
                counts[store.rawValue] = try byteCount(output)
            }
            guard !hashes.isEmpty else { throw ReleaseBackupError.noStores }
            let manifest = ReleaseBackupManifest(files: hashes, byteCounts: counts)
            try JSONEncoder().encode(manifest).write(to: staging.appending(path: "manifest.json"), options: [.atomic, .completeFileProtection])
            try validate(staging)
            if manager.fileExists(atPath: archive.path) { throw ReleaseBackupError.invalidArchive }
            try manager.moveItem(at: staging, to: archive)
            return manifest
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    public func restoreSnapshot(from archiveRoot: URL, toEmptyStoreRoot storeRoot: URL) throws -> ReleaseBackupManifest {
        let archive = archiveRoot.standardizedFileURL
        let destination = storeRoot.standardizedFileURL
        guard archive != destination else { throw ReleaseBackupError.invalidArchive }
        let manifest = try validate(archive)
        if manager.fileExists(atPath: destination.path),
           !(try manager.contentsOfDirectory(atPath: destination.path)).isEmpty {
            throw ReleaseBackupError.destinationNotEmpty
        }
        let staging = destination.appendingPathExtension("restore-staging")
        try? manager.removeItem(at: staging)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        do {
            for name in manifest.files.keys {
                let output = staging.appending(path: name)
                try manager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.copyItem(at: archive.appending(path: name), to: output)
            }
            if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
            try manager.moveItem(at: staging, to: destination)
            return manifest
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    @discardableResult
    public func validate(_ archive: URL) throws -> ReleaseBackupManifest {
        guard let data = try? Data(contentsOf: archive.appending(path: "manifest.json")),
              let manifest = try? JSONDecoder().decode(ReleaseBackupManifest.self, from: data),
              manifest.schemaVersion == ReleaseBackupManifest.schemaVersion,
              !manifest.files.isEmpty else { throw ReleaseBackupError.invalidArchive }
        for (name, expected) in manifest.files {
            guard ReleaseBackupStore(rawValue: name) != nil else { throw ReleaseBackupError.invalidArchive }
            let file = archive.appending(path: name)
            guard let actualChecksum = try? checksum(file),
                  let actualBytes = try? byteCount(file),
                  actualChecksum == expected,
                  actualBytes == manifest.byteCounts[name] else { throw ReleaseBackupError.invalidArchive }
        }
        return manifest
    }

    private func checksum(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func byteCount(_ url: URL) throws -> Int64 {
        Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }
}
