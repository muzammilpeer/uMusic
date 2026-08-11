import Foundation
import Testing

@Test("Maintained Xcode hosts own explicit bundle identities")
func hostBundleIdentifiersAreExplicit() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let project = try String(contentsOf: root.appending(path: "Apps/UMusicApp/UMusicApp.xcodeproj/project.pbxproj"), encoding: .utf8)
    for identifier in [
        "uk.muzammilpeer.umusic.v2;",
        "uk.muzammilpeer.umusic.v2.share;",
        "uk.muzammilpeer.umusic.v2.inspector;",
    ] {
        #expect(project.contains("PRODUCT_BUNDLE_IDENTIFIER = \(identifier)"))
    }
    let package = try String(contentsOf: root.appending(path: "Package.swift"), encoding: .utf8)
    #expect(!package.contains(".executable(name: \"UMusicApp\""))
    #expect(!package.contains(".executableTarget(\n            name: \"UMusicApp\""))
}
