import Foundation
import Testing
import UMusicDomain
import UMusicInspector

@Test("Inspector accepts complete packages and rejects malformed packages")
func inspectorPackageValidation() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let package = root.appending(path: "fixture.umusicresearch", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try Data("{}\n".utf8).write(to: package.appending(path: "events.jsonl"))
    let manifest = ResearchExportManifest(schemaVersion: 1, exportKind: .sanitized, generatedAt: Date(), files: ["events.jsonl"], recordCounts: ["events.jsonl": 1], excludedFields: [])
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(to: package.appending(path: "manifest.json"))
    let inspected = try ReadOnlyResearchInspector.inspect(packageAt: package).manifest
    #expect(inspected.schemaVersion == manifest.schemaVersion)
    #expect(inspected.exportKind == manifest.exportKind)
    #expect(inspected.files == manifest.files)
    #expect(inspected.recordCounts == manifest.recordCounts)
    try FileManager.default.removeItem(at: package.appending(path: "events.jsonl"))
    #expect(throws: ResearchExportError.malformedPackage) { try ReadOnlyResearchInspector.inspect(packageAt: package) }
    try? FileManager.default.removeItem(at: root)
}

@Test("Inspector copies stores before opening and marks the copy read-only")
func inspectorReadOnlyCopy() throws {
    let source = FileManager.default.temporaryDirectory.appending(path: "inspector-source-\(UUID()).sqlite")
    try Data("live".utf8).write(to: source)
    let copy = try ReadOnlyResearchInspector.protectedReadOnlyCopy(of: source)
    #expect(try Data(contentsOf: source) == Data("live".utf8))
    #expect(copy != source)
    let permissions = try #require(FileManager.default.attributesOfItem(atPath: copy.path)[.posixPermissions] as? NSNumber)
    #expect(permissions.intValue & 0o222 == 0)
    try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: copy)
}
