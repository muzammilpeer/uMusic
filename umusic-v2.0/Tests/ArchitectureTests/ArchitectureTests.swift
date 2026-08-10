import Foundation
import Testing

private struct ModuleRule {
    let module: String
    let allowedImports: Set<String>
}

private let rules = [
    ModuleRule(module: "UMusicDomain", allowedImports: ["Foundation"]),
    ModuleRule(module: "UMusicSupport", allowedImports: ["Foundation", "os"]),
    ModuleRule(module: "UMusicData", allowedImports: ["CoreData", "Foundation", "UMusicDomain", "UMusicSupport"]),
    ModuleRule(module: "UMusicNetworking", allowedImports: ["Foundation", "UMusicDomain", "UMusicSupport"]),
    ModuleRule(module: "UMusicPlayback", allowedImports: ["AVFoundation", "Foundation", "MediaPlayer", "UMusicDomain", "UMusicSupport"]),
    ModuleRule(module: "UMusicOffline", allowedImports: ["CryptoKit", "Foundation", "UMusicDomain", "UMusicSupport"]),
    ModuleRule(module: "UMusicContext", allowedImports: ["AVFoundation", "Foundation", "Network", "UMusicDomain", "UMusicSupport"]),
    ModuleRule(module: "UMusicLearning", allowedImports: ["Foundation", "UMusicDomain", "UMusicML", "UMusicSupport"]),
    ModuleRule(module: "UMusicML", allowedImports: ["CoreML", "CryptoKit", "Foundation", "UMusicDomain", "UMusicSupport"]),
    ModuleRule(module: "UMusicTelemetry", allowedImports: ["UMusicDomain", "UMusicSupport"]),
    ModuleRule(module: "UMusicSecurity", allowedImports: ["Foundation", "Security", "UMusicDomain", "UMusicSupport"]),
    ModuleRule(module: "UMusicCore", allowedImports: ["Foundation", "UMusicContext", "UMusicData", "UMusicDomain", "UMusicLearning", "UMusicML", "UMusicNetworking", "UMusicOffline", "UMusicPlayback", "UMusicSecurity", "UMusicSupport"]),
    ModuleRule(module: "UMusicImportClient", allowedImports: ["Foundation", "Security", "UMusicSupport"]),
    ModuleRule(module: "UMusicPresentation", allowedImports: ["Foundation", "Observation", "SwiftUI", "UMusicCore"]),
]

private func packageRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func swiftFiles(in directory: URL) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else { return [] }

    return try enumerator.compactMap { item in
        guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
        return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true ? url : nil
    }
}

private func imports(in file: URL) throws -> Set<String> {
    let source = try String(contentsOf: file, encoding: .utf8)
    return Set(source.split(separator: "\n").compactMap { line in
        let text = line.trimmingCharacters(in: .whitespaces)
        let markers = ["import ", "@_exported import ", "@testable import "]
        guard let marker = markers.first(where: { text.hasPrefix($0) }) else { return nil }
        return text.dropFirst(marker.count).split(separator: " ").first.map(String.init)
    })
}

@Test("Source modules import only their declared architecture dependencies")
func sourceDependencyDirections() throws {
    let sources = packageRoot().appending(path: "Sources", directoryHint: .isDirectory)

    for rule in rules {
        let directory = sources.appending(path: rule.module, directoryHint: .isDirectory)
        for file in try swiftFiles(in: directory) {
            let unexpected = try imports(in: file).subtracting(rule.allowedImports)
            #expect(unexpected.isEmpty, "\(rule.module)/\(file.lastPathComponent) imports forbidden modules: \(unexpected)")
        }
    }
}

@Test("The extension-safe product contains no sensitive Apple framework imports")
func importClientIsExtensionSafe() throws {
    let directory = packageRoot().appending(
        path: "Sources/UMusicImportClient",
        directoryHint: .isDirectory
    )
    let forbidden = Set(["AVFoundation", "CoreData", "CoreLocation", "CoreML", "CoreMotion", "HealthKit", "MediaPlayer", "SwiftUI"])

    for file in try swiftFiles(in: directory) {
        #expect(try imports(in: file).isDisjoint(with: forbidden))
    }
}

@Test("Public framework sources do not expose infrastructure implementation types")
func publicFacadeDoesNotLeakInfrastructure() throws {
    let directory = packageRoot().appending(path: "Sources/UMusicCore", directoryHint: .isDirectory)
    let forbiddenTokens = ["AVPlayer", "NSManagedObject", "NSManagedObjectContext", "SecItem", "MLMultiArray"]

    for file in try swiftFiles(in: directory) {
        let source = try String(contentsOf: file, encoding: .utf8)
        for token in forbiddenTokens {
            #expect(!source.contains(token), "\(file.lastPathComponent) exposes or references \(token)")
        }
    }
}
