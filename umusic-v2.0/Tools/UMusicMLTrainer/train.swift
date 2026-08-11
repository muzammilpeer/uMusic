import CreateML
import CryptoKit
import Foundation
import TabularData

let features = ["heuristic_score", "completion_rate", "skip_rate", "exposure_log", "offline", "local_hour_sin", "local_hour_cos", "release_year_scaled"]
let arguments = CommandLine.arguments
guard let outputIndex = arguments.firstIndex(of: "--output"), arguments.indices.contains(outputIndex + 1),
      let keyIndex = arguments.firstIndex(of: "--signing-key"), arguments.indices.contains(keyIndex + 1) else {
    FileHandle.standardError.write(Data("Usage: swift train.swift --bootstrap --output <Resources> --signing-key <private-key-file>\n".utf8))
    exit(2)
}
guard arguments.contains("--bootstrap") else {
    FileHandle.standardError.write(Data("Only --bootstrap is currently supported. Export-trained feature reconstruction is intentionally not faked.\n".utf8))
    exit(2)
}

let output = URL(fileURLWithPath: arguments[outputIndex + 1], isDirectory: true)
let privateKeyURL = URL(fileURLWithPath: arguments[keyIndex + 1])
let manager = FileManager.default
try manager.createDirectory(at: output, withIntermediateDirectories: true)
let work = manager.temporaryDirectory.appending(path: "umusic-ml-trainer-\(UUID().uuidString)", directoryHint: .isDirectory)
try manager.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: work) }

// This cold-start prior learns a bounded refinement of the existing heuristic
// from deterministic curated listening scenarios. It is useful before personal
// history exists, but is never represented as population-trained evidence.
var csv = (features + ["score"]).joined(separator: ",") + "\n"
for index in 0..<4_096 {
    var generator = SplitMix64(seed: UInt64(index + 1))
    let heuristic = generator.nextDouble(in: -4...4)
    let completion = generator.nextDouble(in: 0...1)
    let skip = generator.nextDouble(in: 0...1)
    let exposure = generator.nextDouble(in: 0...5)
    let offline = generator.nextDouble() > 0.5 ? 1.0 : 0.0
    let hour = generator.nextDouble(in: 0...(2 * Double.pi))
    let year = generator.nextDouble(in: 0.4...0.65)
    let score = heuristic + 1.4 * completion - 1.8 * skip - 0.08 * exposure + 0.15 * offline + 0.04 * sin(hour) + 0.03 * cos(hour) + 0.05 * year
    let row = [heuristic, completion, skip, exposure, offline, sin(hour), cos(hour), year, score]
        .map { String($0) }
        .joined(separator: ",")
    csv.append(row + "\n")
}
let csvURL = work.appending(path: "bootstrap-training.csv")
try Data(csv.utf8).write(to: csvURL, options: .atomic)
let table = try DataFrame(contentsOfCSVFile: csvURL)
let model = try MLBoostedTreeRegressor(trainingData: table, targetColumn: "score", featureColumns: features)
let sourceModel = work.appending(path: "UMusicRanker.mlmodel")
try model.write(to: sourceModel, metadata: .init(author: "uMusic", shortDescription: "Curated cold-start music ranker", license: nil, version: "coldstart-prior-1", additional: ["training_source": "deterministic-curated-scenarios"]))

let compiled = output.appending(path: "UMusicRanker.mlmodelc", directoryHint: .isDirectory)
try? manager.removeItem(at: compiled)
let compiler = Process()
compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
compiler.arguments = ["coremlcompiler", "compile", sourceModel.path, output.path]
try compiler.run(); compiler.waitUntilExit()
guard compiler.terminationStatus == 0, manager.fileExists(atPath: compiled.path) else { throw TrainerError.compilationFailed }

let digest = try compiledModelDigest(compiled)
let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: privateKeyURL))
var manifest = Manifest(featureVersion: "ranker-features-1", modelVersion: "coldstart-prior-1", orderedFeatures: features, minimumOSMajorVersion: 17, maximumBatchSize: 200, timeoutMilliseconds: 50, modelSHA256: digest.hex, signature: "", publicKeyID: "umusic-coldstart-1")
manifest.signature = try privateKey.signature(for: signingPayload(digest: digest, manifest: manifest)).base64EncodedString()
let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(manifest).write(to: output.appending(path: "ranker-feature-manifest.json"), options: .atomic)
try encoder.encode([manifest.publicKeyID: privateKey.publicKey.rawRepresentation.base64EncodedString()]).write(to: output.appending(path: "ranker-trusted-keys.json"), options: .atomic)
let report: [String: Any] = ["model_version": manifest.modelVersion, "training_source": "deterministic-curated-scenarios", "personalized": false, "examples": 4096, "training_maximum_error": model.trainingMetrics.maximumError, "validation_maximum_error": model.validationMetrics.maximumError]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appending(path: "ranker-training-report.json"), options: .atomic)
print("Generated \(manifest.modelVersion) with SHA-256 \(manifest.modelSHA256)")

struct Manifest: Codable {
    let schemaVersion = 1
    let featureVersion: String
    let modelVersion: String
    let orderedFeatures: [String]
    let minimumOSMajorVersion: Int
    let maximumBatchSize: Int
    let timeoutMilliseconds: Int
    let modelSHA256: String
    var signature: String
    let publicKeyID: String
}

enum TrainerError: Error { case compilationFailed }

struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
    mutating func nextDouble() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func nextDouble(in range: ClosedRange<Double>) -> Double { range.lowerBound + nextDouble() * (range.upperBound - range.lowerBound) }
}

func compiledModelDigest(_ root: URL) throws -> Data {
    let keys: Set<URLResourceKey> = [.isRegularFileKey]
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { throw TrainerError.compilationFailed }
    let files = enumerator.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: keys).isRegularFile) == true }.sorted { $0.path < $1.path }
    var hasher = SHA256()
    for file in files {
        let relative = String(file.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        hasher.update(data: Data(relative.utf8)); hasher.update(data: Data([0])); hasher.update(data: try Data(contentsOf: file))
    }
    return Data(hasher.finalize())
}

func signingPayload(digest: Data, manifest: Manifest) -> Data {
    let fields = [String(manifest.schemaVersion), manifest.featureVersion, manifest.modelVersion, manifest.orderedFeatures.joined(separator: ","), String(manifest.minimumOSMajorVersion), String(manifest.maximumBatchSize), String(manifest.timeoutMilliseconds), manifest.modelSHA256.lowercased(), manifest.publicKeyID]
    return digest + Data(fields.joined(separator: "\n").utf8)
}

extension Data { var hex: String { map { String(format: "%02x", $0) }.joined() } }
