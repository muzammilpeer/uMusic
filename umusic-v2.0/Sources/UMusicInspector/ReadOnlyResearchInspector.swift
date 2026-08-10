import Foundation
import UMusicDomain

public struct InspectedResearchPackage: Equatable, Sendable {
    public let manifest: ResearchExportManifest
    public let packageURL: URL
    public init(manifest: ResearchExportManifest, packageURL: URL) { self.manifest = manifest; self.packageURL = packageURL }
}

public enum ReadOnlyResearchInspector {
    public static func inspect(packageAt url: URL) throws -> InspectedResearchPackage {
        let manifestURL = url.appending(path: "manifest.json")
        guard url.pathExtension == "umusicresearch", FileManager.default.fileExists(atPath: manifestURL.path) else { throw ResearchExportError.malformedPackage }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(ResearchExportManifest.self, from: Data(contentsOf: manifestURL)), manifest.schemaVersion == 1 else { throw ResearchExportError.malformedPackage }
        guard manifest.files.allSatisfy({ file in !file.contains("..") && FileManager.default.fileExists(atPath: url.appending(path: file).path) }) else { throw ResearchExportError.malformedPackage }
        return InspectedResearchPackage(manifest: manifest, packageURL: url)
    }

    public static func protectedReadOnlyCopy(of source: URL, temporaryRoot: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let destination = temporaryRoot.appending(path: "UMusicInspector-\(UUID().uuidString)-\(source.lastPathComponent)")
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o400, .protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
        return destination
    }
}
