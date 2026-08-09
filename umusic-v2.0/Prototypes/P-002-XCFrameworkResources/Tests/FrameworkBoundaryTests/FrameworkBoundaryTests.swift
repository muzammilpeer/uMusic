import Foundation
import Testing
import UMusicCoreProbe
import UMusicImportClientProbe

@Test("The core product resolves and decodes its bundled resource")
func bundledManifestLoads() throws {
    let manifest = try ProbeResourceLoader.loadManifest()
    #expect(manifest.featureSchemaVersion == 1)
    #expect(manifest.modelID == "prototype-resource")
    #expect(manifest.modelVersion == "0.0.1")
}

@Test("The extension-safe product accepts only HTTP and HTTPS URLs")
func importClientSchemeBoundary() throws {
    let request = try ImportRequest(
        sourceURL: #require(URL(string: "https://example.invalid/watch/1")),
        idempotencyKey: UUID()
    )
    #expect(request.sourceURL.scheme == "https")

    #expect(throws: ImportRequestError.unsupportedScheme) {
        try ImportRequest(
            sourceURL: #require(URL(string: "file:///private/example.mp3")),
            idempotencyKey: UUID()
        )
    }
}

