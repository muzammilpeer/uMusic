import CryptoKit
import Foundation
import UMusicDomain
import UMusicSupport

public struct RankerFeatureManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let featureVersion: String
    public let modelVersion: String
    public let orderedFeatures: [String]
    public let minimumOSMajorVersion: Int
    public let maximumBatchSize: Int
    public let timeoutMilliseconds: Int
    public let modelSHA256: String
    public let signature: String
    public let publicKeyID: String
    public init(schemaVersion: Int = 1, featureVersion: String, modelVersion: String, orderedFeatures: [String], minimumOSMajorVersion: Int, maximumBatchSize: Int = 200, timeoutMilliseconds: Int = 50, modelSHA256: String, signature: String, publicKeyID: String) {
        self.schemaVersion = schemaVersion; self.featureVersion = featureVersion; self.modelVersion = modelVersion
        self.orderedFeatures = orderedFeatures; self.minimumOSMajorVersion = minimumOSMajorVersion
        self.maximumBatchSize = min(max(maximumBatchSize, 1), 1_000); self.timeoutMilliseconds = min(max(timeoutMilliseconds, 1), 500)
        self.modelSHA256 = modelSHA256; self.signature = signature; self.publicKeyID = publicKeyID
    }
}

public enum ModelLifecycleMode: String, Codable, Sendable { case disabled, shadow, active }
public enum ModelRankerError: Error, Equatable { case badSignature, corruptModel, incompatibleSchema, incompatibleOS, invalidFeatures, invalidOutput, timeout, canaryFailed, unavailable }

public struct ModelEvaluationSnapshot: Codable, Equatable, Sendable {
    public let mode: ModelLifecycleMode
    public let modelVersion: String?
    public let attempts: Int
    public let successes: Int
    public let failures: Int
    public let timeouts: Int
    public init(mode: ModelLifecycleMode, modelVersion: String?, attempts: Int, successes: Int, failures: Int, timeouts: Int) { self.mode = mode; self.modelVersion = modelVersion; self.attempts = attempts; self.successes = successes; self.failures = failures; self.timeouts = timeouts }
}

public protocol ModelBatchScoring: Sendable { func scores(for batch: [[Double]], orderedFeatures: [String]) async throws -> [Double] }

public struct ValidatedRankerManifest: Sendable {
    public let manifest: RankerFeatureManifest
    fileprivate init(_ manifest: RankerFeatureManifest) { self.manifest = manifest }
}

public enum ModelRankingOutcome: Sendable {
    case scored(scores: [Double], mode: ModelLifecycleMode, modelVersion: String, featureVersion: String)
    case fallback(code: String)
}

public enum SignedModelValidator {
    public static func validate(modelData: Data, manifest: RankerFeatureManifest, trustedPublicKeys: [String: Data], currentOSMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) throws -> ValidatedRankerManifest {
        try validate(modelDigest: Data(SHA256.hash(data: modelData)), manifest: manifest, trustedPublicKeys: trustedPublicKeys, currentOSMajorVersion: currentOSMajorVersion)
    }

    public static func validate(modelAt url: URL, manifest: RankerFeatureManifest, trustedPublicKeys: [String: Data], currentOSMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) throws -> ValidatedRankerManifest {
        let manager = FileManager.default
        let canonicalRoot = url.standardizedFileURL.resolvingSymlinksInPath()
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = manager.enumerator(at: canonicalRoot, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { throw ModelRankerError.corruptModel }
        let files = enumerator.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: keys).isRegularFile) == true }.sorted { $0.path < $1.path }
        guard !files.isEmpty else { throw ModelRankerError.corruptModel }
        var hasher = SHA256()
        for file in files {
            let relativePath = String(file.path.dropFirst(canonicalRoot.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            hasher.update(data: Data(relativePath.utf8)); hasher.update(data: Data([0]))
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            while true {
                let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
        }
        return try validate(modelDigest: Data(hasher.finalize()), manifest: manifest, trustedPublicKeys: trustedPublicKeys, currentOSMajorVersion: currentOSMajorVersion)
    }

    public static func validate(modelDigest digest: Data, manifest: RankerFeatureManifest, trustedPublicKeys: [String: Data], currentOSMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) throws -> ValidatedRankerManifest {
        guard manifest.schemaVersion == 1, manifest.orderedFeatures == ModelRankerLifecycle.supportedFeatures else { throw ModelRankerError.incompatibleSchema }
        guard currentOSMajorVersion >= manifest.minimumOSMajorVersion else { throw ModelRankerError.incompatibleOS }
        let expected = digest.map { String(format: "%02x", $0) }.joined()
        guard expected == manifest.modelSHA256.lowercased() else { throw ModelRankerError.corruptModel }
        let payload = signingPayload(modelDigest: digest, manifest: manifest)
        guard let keyData = trustedPublicKeys[manifest.publicKeyID], let signature = Data(base64Encoded: manifest.signature), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData), key.isValidSignature(signature, for: payload) else { throw ModelRankerError.badSignature }
        return ValidatedRankerManifest(manifest)
    }

    public static func signingPayload(modelDigest: Data, manifest: RankerFeatureManifest) -> Data {
        let fields = [String(manifest.schemaVersion), manifest.featureVersion, manifest.modelVersion, manifest.orderedFeatures.joined(separator: ","), String(manifest.minimumOSMajorVersion), String(manifest.maximumBatchSize), String(manifest.timeoutMilliseconds), manifest.modelSHA256.lowercased(), manifest.publicKeyID]
        return modelDigest + Data(fields.joined(separator: "\n").utf8)
    }
}

public actor ModelRankerLifecycle {
    public static let supportedFeatures = ["heuristic_score", "completion_rate", "skip_rate", "exposure_log", "offline", "local_hour_sin", "local_hour_cos", "release_year_scaled"]
    private let manifest: RankerFeatureManifest
    private let scorer: any ModelBatchScoring
    private var mode: ModelLifecycleMode = .disabled
    private var attempts = 0, successes = 0, failures = 0, timeouts = 0

    public init(validated: ValidatedRankerManifest, scorer: any ModelBatchScoring) { self.manifest = validated.manifest; self.scorer = scorer }

    public func enableShadow() async throws { try await canary(); mode = .shadow }
    public func activate() async throws { try await canary(); mode = .active }
    public func disable() { mode = .disabled }
    public func evaluationSnapshot() -> ModelEvaluationSnapshot { .init(mode: mode, modelVersion: manifest.modelVersion, attempts: attempts, successes: successes, failures: failures, timeouts: timeouts) }

    public func rank(_ features: [[Double]]) async -> ModelRankingOutcome {
        let interval = PerformanceSignposts.begin("ModelRank"); defer { PerformanceSignposts.end(interval) }
        guard mode != .disabled else { return .fallback(code: "model_disabled") }
        guard !features.isEmpty, features.count <= manifest.maximumBatchSize, features.allSatisfy({ $0.count == manifest.orderedFeatures.count && $0.allSatisfy(\.isFinite) }) else { return failed(.invalidFeatures) }
        let bounded = features.map { $0.map { min(max($0, -1_000_000), 1_000_000) } }
        attempts += 1
        do {
            let scores = try await timedScores(bounded)
            guard scores.count == bounded.count, scores.allSatisfy(\.isFinite) else { return failed(.invalidOutput) }
            successes += 1
            return .scored(scores: scores, mode: mode, modelVersion: manifest.modelVersion, featureVersion: manifest.featureVersion)
        } catch let error as ModelRankerError { return failed(error) }
        catch { return failed(.unavailable) }
    }

    private func canary() async throws {
        let zero = Array(repeating: 0.0, count: manifest.orderedFeatures.count)
        let scores = try await timedScores([zero])
        guard scores.count == 1, scores[0].isFinite else { throw ModelRankerError.canaryFailed }
    }

    private func timedScores(_ features: [[Double]]) async throws -> [Double] {
        let scorer = self.scorer, ordered = manifest.orderedFeatures, timeout = manifest.timeoutMilliseconds
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ModelResultGate(continuation)
            Task { do { await gate.finish(.success(try await scorer.scores(for: features, orderedFeatures: ordered))) } catch { await gate.finish(.failure(error)) } }
            Task { try? await Task.sleep(for: .milliseconds(timeout)); await gate.finish(.failure(ModelRankerError.timeout)) }
        }
    }

    private func failed(_ error: ModelRankerError) -> ModelRankingOutcome {
        failures += 1; if error == .timeout { timeouts += 1 }
        if mode == .active { mode = .disabled }
        return .fallback(code: String(describing: error))
    }
}

private actor ModelResultGate {
    private var continuation: CheckedContinuation<[Double], any Error>?
    init(_ continuation: CheckedContinuation<[Double], any Error>) { self.continuation = continuation }
    func finish(_ result: Result<[Double], any Error>) {
        guard let continuation else { return }; self.continuation = nil; continuation.resume(with: result)
    }
}
