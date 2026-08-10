import Foundation

public enum ImportProvider: String, Codable, Sendable {
    case youtube
    case directMP3 = "direct_mp3"
}

public struct ImportRequest: Codable, Equatable, Sendable, Identifiable {
    public let sourceURL: URL
    public let provider: ImportProvider
    public let idempotencyKey: UUID
    public var id: UUID { idempotencyKey }

    public init(sourceURL: URL, idempotencyKey: UUID = UUID()) throws {
        let normalized = try ImportURLPolicy.normalize(sourceURL)
        self.sourceURL = normalized.url
        self.provider = normalized.provider
        self.idempotencyKey = idempotencyKey
    }
}

public enum ImportRequestError: Error, Equatable, Sendable {
    case unsupportedScheme
    case urlTooLong
    case malformedURL
    case credentialsNotAllowed
    case unsupportedProvider
}

public enum ImportURLPolicy {
    public static let maximumLength = 2_000
    private static let youtubeHosts = Set(["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"])

    public static func normalize(_ sourceURL: URL) throws -> (url: URL, provider: ImportProvider) {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(), !host.isEmpty else { throw ImportRequestError.unsupportedScheme }
        guard components.user == nil, components.password == nil else { throw ImportRequestError.credentialsNotAllowed }
        components.scheme = "https"
        components.host = host
        components.fragment = nil
        if (scheme == "http" && components.port == 80) || (scheme == "https" && components.port == 443) { components.port = nil }
        guard let url = components.url, url.absoluteString.utf8.count <= maximumLength else { throw ImportRequestError.urlTooLong }
        let provider: ImportProvider
        if youtubeHosts.contains(host) {
            provider = .youtube
        } else if components.path.lowercased().hasSuffix(".mp3") {
            provider = .directMP3
        } else {
            throw ImportRequestError.unsupportedProvider
        }
        return (url, provider)
    }

    public static func firstSupportedURL(in representations: [URL]) throws -> URL {
        for representation in representations {
            if let normalized = try? normalize(representation).url { return normalized }
        }
        throw ImportRequestError.unsupportedProvider
    }
}

public enum ImportJobState: String, Codable, Sendable { case pending, running, completed, partial, failed }

public struct ImportJob: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let status: ImportJobState
    public let importedCount: Int
    public let errorCode: String?
    public init(id: UUID, status: ImportJobState, importedCount: Int = 0, errorCode: String? = nil) {
        self.id = id; self.status = status; self.importedCount = importedCount; self.errorCode = errorCode
    }
    enum CodingKeys: String, CodingKey { case id, status, importedCount = "imported_count", errorCode = "error_code" }
}

public enum ImportClientError: Error, Equatable, Sendable {
    case authenticationUnavailable
    case serverUnavailable
    case providerUnavailable
    case authorizationAttestationRequired
    case invalidResponse
    case offline
}
