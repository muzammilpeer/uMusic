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

    public static func bundledRankerModelURL() -> URL? { Bundle.module.url(forResource: "UMusicRanker", withExtension: "mlmodelc") }
}
