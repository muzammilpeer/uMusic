import Foundation
import UMusicDomain
import UMusicSupport

public enum AuthenticationTransportError: Error, Equatable, Sendable {
    case offline(requestID: String?)
    case unauthorized(requestID: String?)
    case revoked(requestID: String?)
    case server(code: String, retryable: Bool, requestID: String?)
    case invalidResponse
    case incompatibleServer
}

public actor URLSessionAuthenticationAPI: AuthenticationAPI {
    private let session: URLSession
    private let installationID: UUID
    private let platform: String
    private let appVersion: String

    public init(session: URLSession = .shared, installationID: UUID, platform: String, appVersion: String) {
        self.session = session
        self.installationID = installationID
        self.platform = platform
        self.appVersion = appVersion
    }

    public func bootstrap(server: ServerConfiguration) async throws -> ServerBootstrap {
        var request = URLRequest(url: endpoint("api/v2/bootstrap", server: server))
        request.httpMethod = "GET"
        let response: BootstrapResponse = try await send(request)
        return ServerBootstrap(
            serverID: response.serverID,
            apiVersion: response.apiVersion,
            schemaVersion: response.schemaVersion,
            capabilities: Set(response.capabilities.map(ServerCapability.init(rawValue:))),
            libraryCount: response.libraryCount
        )
    }

    public func createSession(server: ServerConfiguration, username: String, password: String) async throws -> SessionTokens {
        var request = URLRequest(url: endpoint("api/v2/auth/session", server: server))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SessionRequest(
            username: username,
            password: password,
            device: .init(installationID: installationID, platform: platform, appVersion: appVersion)
        ))
        let response: SessionResponse = try await send(request)
        return response.tokens
    }

    public func refreshSession(server: ServerConfiguration, refreshToken: String) async throws -> SessionTokens {
        var request = URLRequest(url: endpoint("api/v2/auth/session/refresh", server: server))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])
        let response: SessionResponse = try await send(request)
        return response.tokens
    }

    public func revokeSession(server: ServerConfiguration, accessToken: String) async throws {
        var request = URLRequest(url: endpoint("api/v2/auth/session/logout", server: server))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let _: EmptyResponse = try await send(request, acceptsEmptyResponse: true)
    }

    private func endpoint(_ path: String, server: ServerConfiguration) -> URL {
        server.baseURL.appending(path: path)
    }

    private func send<Response: Decodable>(
        _ request: URLRequest, acceptsEmptyResponse: Bool = false
    ) async throws -> Response {
        do {
            let (data, rawResponse) = try await session.data(for: request)
            guard let response = rawResponse as? HTTPURLResponse else { throw AuthenticationTransportError.invalidResponse }
            let requestID = response.value(forHTTPHeaderField: "X-Request-ID")
            guard (200..<300).contains(response.statusCode) else {
                if response.statusCode == 401 { throw AuthenticationTransportError.unauthorized(requestID: requestID) }
                if response.statusCode == 403 { throw AuthenticationTransportError.revoked(requestID: requestID) }
                let body = try? decoder.decode(APIErrorResponse.self, from: data)
                throw AuthenticationTransportError.server(
                    code: body?.code ?? "http_\(response.statusCode)",
                    retryable: body?.retryable ?? (response.statusCode >= 500),
                    requestID: body?.requestID ?? requestID
                )
            }
            if acceptsEmptyResponse, data.isEmpty, let empty = EmptyResponse() as? Response {
                return empty
            }
            return try decoder.decode(Response.self, from: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AuthenticationTransportError {
            throw error
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost].contains(error.code) {
            throw AuthenticationTransportError.offline(requestID: nil)
        } catch {
            throw AuthenticationTransportError.invalidResponse
        }
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let text = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) { return date }
            let standard = ISO8601DateFormatter()
            guard let date = standard.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date")
            }
            return date
        }
        return decoder
    }
}

private struct EmptyResponse: Decodable {}

private struct BootstrapResponse: Decodable {
    let serverID: String
    let apiVersion: String
    let schemaVersion: Int
    let capabilities: [String]
    let libraryCount: Int
    enum CodingKeys: String, CodingKey {
        case serverID = "server_id"; case apiVersion = "api_version"; case schemaVersion = "schema_version"
        case capabilities; case libraryCount = "library_count"
    }
}

private struct SessionRequest: Encodable {
    let username: String
    let password: String
    let device: Device
    struct Device: Encodable {
        let installationID: UUID; let platform: String; let appVersion: String
        enum CodingKeys: String, CodingKey { case installationID = "installation_id"; case platform; case appVersion = "app_version" }
    }
}

private struct SessionResponse: Decodable {
    let accessToken: String; let expiresAt: Date; let refreshToken: String; let user: User; let capabilities: [String]
    struct User: Decodable { let id: UUID; let displayName: String; enum CodingKeys: String, CodingKey { case id; case displayName = "display_name" } }
    enum CodingKeys: String, CodingKey { case accessToken = "access_token"; case expiresAt = "expires_at"; case refreshToken = "refresh_token"; case user; case capabilities }
    var tokens: SessionTokens { SessionTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt, user: .init(id: user.id, displayName: user.displayName), capabilities: Set(capabilities.map(ServerCapability.init(rawValue:)))) }
}

private struct APIErrorResponse: Decodable {
    let code: String; let retryable: Bool; let requestID: String?
    enum CodingKeys: String, CodingKey { case code; case retryable; case requestID = "request_id" }
}
