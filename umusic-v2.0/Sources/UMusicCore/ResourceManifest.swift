import Foundation
import UMusicML

public struct UMusicResourceManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let frameworkVersion: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case frameworkVersion = "framework_version"
    }
}

public struct ReleaseFreezeManifest: Codable, Equatable, Sendable {
    public let releaseTrain: String
    public let frameworkVersion: String
    public let publicAPIBaseline: Int
    public let schemas: [String: Int]
    public let status: String

    enum CodingKeys: String, CodingKey {
        case releaseTrain = "release_train"
        case frameworkVersion = "framework_version"
        case publicAPIBaseline = "public_api_baseline"
        case schemas, status
    }
}

public enum UMusicResources {
    public static func manifest() throws -> UMusicResourceManifest {
        guard let url = Bundle.module.url(forResource: "resource-manifest", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(
            UMusicResourceManifest.self,
            from: Data(contentsOf: url)
        )
    }

    public static func rankerFeatureManifest() throws -> RankerFeatureManifest {
        guard let url = Bundle.module.url(forResource: "ranker-feature-manifest", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode(RankerFeatureManifest.self, from: Data(contentsOf: url))
    }

    public static func releaseFreezeManifest() throws -> ReleaseFreezeManifest {
        guard let url = Bundle.module.url(forResource: "release-freeze", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode(ReleaseFreezeManifest.self, from: Data(contentsOf: url))
    }

    public static func bundledRankerModelURL() -> URL? { Bundle.module.url(forResource: "UMusicRanker", withExtension: "mlmodelc") }

    public static func trustedRankerPublicKeys() throws -> [String: Data] {
        guard let url = Bundle.module.url(forResource: "ranker-trusted-keys", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        let encoded = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        return try encoded.mapValues { value in
            guard let data = Data(base64Encoded: value) else { throw CocoaError(.fileReadCorruptFile) }
            return data
        }
    }

    public static func bundledRanker() throws -> BundledRanker {
        guard let modelURL = bundledRankerModelURL() else { throw ModelRankerError.unavailable }
        let manifest = try rankerFeatureManifest()
        let validated = try SignedModelValidator.validate(modelAt: modelURL, manifest: manifest, trustedPublicKeys: try trustedRankerPublicKeys())
        let scorer = try CoreMLModelScorer(compiledModelURL: modelURL)
        return BundledRanker(manifest: manifest, lifecycle: ModelRankerLifecycle(validated: validated, scorer: scorer))
    }
}

public struct BundledRanker: Sendable {
    public let manifest: RankerFeatureManifest
    public let lifecycle: ModelRankerLifecycle
}
