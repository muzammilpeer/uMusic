import Foundation
import UMusicDomain

public enum ServerURLValidationError: Error, Equatable, Sendable {
    case empty
    case malformed
    case missingHost
    case credentialsInURL
    case queryOrFragmentNotAllowed
    case insecureTransport
}

public enum ServerURLValidator {
    public static func normalize(_ rawValue: String, allowsInsecureLocalhost: Bool = false) throws -> ServerConfiguration {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ServerURLValidationError.empty }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate), let host = components.host, !host.isEmpty else {
            throw ServerURLValidationError.missingHost
        }
        guard components.user == nil, components.password == nil else {
            throw ServerURLValidationError.credentialsInURL
        }
        guard components.query == nil, components.fragment == nil else {
            throw ServerURLValidationError.queryOrFragmentNotAllowed
        }

        let scheme = components.scheme?.lowercased()
        let isLocal = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard scheme == "https" || (scheme == "http" && isLocal && allowsInsecureLocalhost) else {
            throw ServerURLValidationError.insecureTransport
        }

        components.scheme = scheme
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !components.path.isEmpty { components.path = "/\(components.path)" }
        guard let url = components.url else { throw ServerURLValidationError.malformed }
        return ServerConfiguration(baseURL: url, allowsInsecureLocalhost: allowsInsecureLocalhost)
    }
}

