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
}
