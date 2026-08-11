import CryptoKit
import Foundation
import Testing
import UMusicCore
import UMusicDomain
import UMusicLearning
import UMusicML

private struct LinearTestScorer: ModelBatchScoring {
    let featureIndex: Int
    func scores(for batch: [[Double]], orderedFeatures: [String]) async throws -> [Double] { batch.map { $0[featureIndex] } }
}

private struct InvalidTestScorer: ModelBatchScoring {
    func scores(for batch: [[Double]], orderedFeatures: [String]) async throws -> [Double] { Array(repeating: .nan, count: batch.count) }
}

private struct SlowTestScorer: ModelBatchScoring {
    func scores(for batch: [[Double]], orderedFeatures: [String]) async throws -> [Double] { try await Task.sleep(for: .milliseconds(150)); return Array(repeating: 0, count: batch.count) }
}

private func modelManifest(timeout: Int = 50, signature: String = "", hash: String = "", keyID: String = "test") -> RankerFeatureManifest {
    .init(featureVersion: "ranker-features-1", modelVersion: "fixture-1", orderedFeatures: ModelRankerLifecycle.supportedFeatures, minimumOSMajorVersion: 14, maximumBatchSize: 200, timeoutMilliseconds: timeout, modelSHA256: hash, signature: signature, publicKeyID: keyID)
}

private func validatedLifecycle(scorer: any ModelBatchScoring, timeout: Int = 50) throws -> ModelRankerLifecycle {
    let model = Data("lifecycle-fixture".utf8), digest = Data(SHA256.hash(data: model)), hash = digest.map { String(format: "%02x", $0) }.joined(), key = Curve25519.Signing.PrivateKey()
    let unsigned = modelManifest(timeout: timeout, hash: hash)
    let signature = try key.signature(for: SignedModelValidator.signingPayload(modelDigest: digest, manifest: unsigned)).base64EncodedString()
    let signed = modelManifest(timeout: timeout, signature: signature, hash: hash)
    let validated = try SignedModelValidator.validate(modelData: model, manifest: signed, trustedPublicKeys: ["test": key.publicKey.rawRepresentation], currentOSMajorVersion: 17)
    return ModelRankerLifecycle(validated: validated, scorer: scorer)
}

@Test("Signed model validation rejects bad signatures, corruption, schema, and OS incompatibility")
func signedModelValidation() throws {
    let model = Data("fixture-model".utf8), digest = Data(SHA256.hash(data: model)), hash = digest.map { String(format: "%02x", $0) }.joined()
    let key = Curve25519.Signing.PrivateKey()
    let unsigned = modelManifest(hash: hash)
    let signature = try key.signature(for: SignedModelValidator.signingPayload(modelDigest: digest, manifest: unsigned)).base64EncodedString()
    let signed = modelManifest(signature: signature, hash: hash)
    _ = try SignedModelValidator.validate(modelData: model, manifest: signed, trustedPublicKeys: ["test": key.publicKey.rawRepresentation], currentOSMajorVersion: 17)
    #expect(throws: ModelRankerError.badSignature) { try SignedModelValidator.validate(modelData: model, manifest: modelManifest(signature: Data("bad".utf8).base64EncodedString(), hash: hash), trustedPublicKeys: ["test": key.publicKey.rawRepresentation], currentOSMajorVersion: 17) }
    #expect(throws: ModelRankerError.corruptModel) { try SignedModelValidator.validate(modelData: Data("changed".utf8), manifest: signed, trustedPublicKeys: ["test": key.publicKey.rawRepresentation], currentOSMajorVersion: 17) }
    let wrongSchema = RankerFeatureManifest(featureVersion: "wrong", modelVersion: "fixture", orderedFeatures: ["unknown"], minimumOSMajorVersion: 14, modelSHA256: hash, signature: signature, publicKeyID: "test")
    #expect(throws: ModelRankerError.incompatibleSchema) { try SignedModelValidator.validate(modelData: model, manifest: wrongSchema, trustedPublicKeys: ["test": key.publicKey.rawRepresentation], currentOSMajorVersion: 17) }
    let future = RankerFeatureManifest(featureVersion: "ranker-features-1", modelVersion: "fixture", orderedFeatures: ModelRankerLifecycle.supportedFeatures, minimumOSMajorVersion: 99, modelSHA256: hash, signature: signature, publicKeyID: "test")
    #expect(throws: ModelRankerError.incompatibleOS) { try SignedModelValidator.validate(modelData: model, manifest: future, trustedPublicKeys: ["test": key.publicKey.rawRepresentation], currentOSMajorVersion: 17) }
}

@Test("Canary enables shadow and active modes with deterministic finite scoring")
func modelCanaryShadowAndActivation() async throws {
    let lifecycle = try validatedLifecycle(scorer: LinearTestScorer(featureIndex: 0))
    try await lifecycle.enableShadow()
    if case .scored(let scores, let mode, _, _) = await lifecycle.rank([[2, 0, 0, 0, 0, 0, 0, 0]]) { #expect(scores == [2]); #expect(mode == .shadow) } else { Issue.record("Expected shadow score") }
    try await lifecycle.activate()
    if case .scored(let first, let mode, _, _) = await lifecycle.rank([[3, 0, 0, 0, 0, 0, 0, 0]]), case .scored(let second, _, _, _) = await lifecycle.rank([[3, 0, 0, 0, 0, 0, 0, 0]]) { #expect(first == second); #expect(mode == .active) } else { Issue.record("Expected active scores") }
}

@Test("NaN input, invalid output, and slow inference fall back and active failure rolls back")
func modelFailureRollback() async throws {
    let invalid = try validatedLifecycle(scorer: LinearTestScorer(featureIndex: 0)); try await invalid.activate()
    if case .fallback(let code) = await invalid.rank([[.nan, 0, 0, 0, 0, 0, 0, 0]]) { #expect(code.contains("invalidFeatures")) } else { Issue.record("Expected invalid feature fallback") }
    #expect(await invalid.evaluationSnapshot().mode == .disabled)

    let badOutput = try validatedLifecycle(scorer: InvalidTestScorer())
    await #expect(throws: ModelRankerError.canaryFailed) { try await badOutput.activate() }

    let slow = try validatedLifecycle(scorer: SlowTestScorer(), timeout: 10)
    await #expect(throws: ModelRankerError.timeout) { try await slow.activate() }
    #expect(await slow.evaluationSnapshot().mode == .disabled)

    let extreme = try validatedLifecycle(scorer: LinearTestScorer(featureIndex: 0)); try await extreme.activate()
    if case .scored(let scores, _, _, _) = await extreme.rank([[Double.greatestFiniteMagnitude, 0, 0, 0, 0, 0, 0, 0]]) { #expect(scores == [1_000_000]) } else { Issue.record("Expected clamped score") }
}

@Test("Active model integrates behind heuristic candidates with reason and version tracing")
func modelRecommendationIntegration() async throws {
    let lifecycle = try validatedLifecycle(scorer: LinearTestScorer(featureIndex: 4)); try await lifecycle.activate()
    let store = LocalLearningStore(url: FileManager.default.temporaryDirectory.appending(path: "model-learning-\(UUID()).json"), modelRanker: lifecycle)
    let preferred = TrackSummary(id: UUID(), title: "Offline", artist: "A"), other = TrackSummary(id: UUID(), title: "Other", artist: "B")
    let result = await store.recommendations(from: [other, preferred], at: Date(), offlineTrackIDs: [preferred.id], excluding: [], limit: 2)
    #expect(result.items.first?.id == preferred.id)
    #expect(result.items.allSatisfy { $0.reasons.contains(.modelRanker) })
    #expect(result.engineVersion == "coreml-fixture-1")
    #expect(result.trace?.mode == .model && result.trace?.modelVersion == "fixture-1")
}

@Test("Bundled cold-start model validates and passes its canary")
func modelResourceLookup() async throws {
    let manifest = try UMusicResources.rankerFeatureManifest()
    #expect(manifest.orderedFeatures == ModelRankerLifecycle.supportedFeatures)
    #expect(manifest.modelVersion == "coldstart-prior-1")
    let bundled = try UMusicResources.bundledRanker()
    try await bundled.lifecycle.enableShadow()
    #expect(await bundled.lifecycle.evaluationSnapshot().mode == .shadow)
}

@Test("Signed model validation is stable through a symlinked bundle path")
func modelSymlinkValidation() throws {
    let modelURL = try #require(UMusicResources.bundledRankerModelURL())
    let link = FileManager.default.temporaryDirectory.appending(path: "ranker-link-\(UUID()).mlmodelc")
    defer { try? FileManager.default.removeItem(at: link) }
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: modelURL)
    _ = try SignedModelValidator.validate(
        modelAt: link,
        manifest: UMusicResources.rankerFeatureManifest(),
        trustedPublicKeys: UMusicResources.trustedRankerPublicKeys()
    )
}

@Test("Synthetic ranker improves over the majority baseline within the local latency diagnostic")
func modelBaselineAndLatency() async throws {
    let lifecycle = try validatedLifecycle(scorer: LinearTestScorer(featureIndex: 1)); try await lifecycle.activate()
    let labels = (0..<200).map { $0.isMultiple(of: 2) }
    let batch: [[Double]] = labels.map { label in [0, label ? 1 : 0, 0, 0, 0, 0, 0, 0] }
    let clock = ContinuousClock(); var samples: [Duration] = []; var accuracy = 0.0
    for _ in 0..<10 {
        var scores: [Double] = []; samples.append(await clock.measure { if case .scored(let value, _, _, _) = await lifecycle.rank(batch) { scores = value } })
        accuracy = Double(zip(scores, labels).filter { ($0.0 >= 0.5) == $0.1 }.count) / Double(labels.count)
    }
    samples.sort(); let p95 = samples[8]
    #expect(accuracy == 1)
    #expect(accuracy > 0.5)
    #expect(p95 < .milliseconds(50))
}
