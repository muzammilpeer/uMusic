import Foundation

public struct ProbeModelManifest: Codable, Equatable, Sendable {
    public let featureSchemaVersion: Int
    public let modelID: String
    public let modelVersion: String
    public let sha256: String

    enum CodingKeys: String, CodingKey {
        case featureSchemaVersion = "feature_schema_version"
        case modelID = "model_id"
        case modelVersion = "model_version"
        case sha256
    }
}

public enum ProbeResourceLoader {
    public static func loadManifest() throws -> ProbeModelManifest {
        guard let url = Bundle.module.url(
            forResource: "model-manifest",
            withExtension: "json"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(
            ProbeModelManifest.self,
            from: Data(contentsOf: url)
        )
    }
}

// This symbol intentionally exists only in the core product. The boundary validation
// checks that the import-client source and archive do not reference it.
public enum PlaybackCapabilityMarker: Sendable {
    case availableInContainingAppOnly
}

