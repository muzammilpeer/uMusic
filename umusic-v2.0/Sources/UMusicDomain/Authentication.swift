import Foundation

public struct ServerConfiguration: Codable, Equatable, Sendable {
    public let baseURL: URL
    public let allowsInsecureLocalhost: Bool

    public init(baseURL: URL, allowsInsecureLocalhost: Bool = false) {
        self.baseURL = baseURL
        self.allowsInsecureLocalhost = allowsInsecureLocalhost
    }
}

public struct ServerCapability: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let catalogSync = ServerCapability(rawValue: "catalog_sync")
    public static let audioStream = ServerCapability(rawValue: "audio_stream")
    public static let remoteImport = ServerCapability(rawValue: "remote_import")
}

public struct ServerBootstrap: Codable, Equatable, Sendable {
    public let serverID: String
    public let apiVersion: String
    public let schemaVersion: Int
    public let capabilities: Set<ServerCapability>
    public let libraryCount: Int

    public init(serverID: String, apiVersion: String, schemaVersion: Int, capabilities: Set<ServerCapability>, libraryCount: Int) {
        self.serverID = serverID
        self.apiVersion = apiVersion
        self.schemaVersion = schemaVersion
        self.capabilities = capabilities
        self.libraryCount = max(libraryCount, 0)
    }
}

public struct AuthenticatedUser: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let displayName: String
    public init(id: UUID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct SessionTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let user: AuthenticatedUser
    public let capabilities: Set<ServerCapability>

    public init(accessToken: String, refreshToken: String, expiresAt: Date, user: AuthenticatedUser, capabilities: Set<ServerCapability>) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.user = user
        self.capabilities = capabilities
    }
}

public struct AuthenticationFailure: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let retryable: Bool
    public let requestID: String?

    public init(code: String, message: String, retryable: Bool, requestID: String? = nil) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.requestID = requestID
    }
}

public enum AuthenticationState: Equatable, Sendable {
    case signedOut
    case validatingServer
    case authenticating
    case authenticated(user: AuthenticatedUser, server: ServerConfiguration, persistsSession: Bool)
    case offline(AuthenticationFailure)
    case expired
    case revoked
    case failed(AuthenticationFailure)
}

public enum LogoutLocalDataDisposition: String, Codable, Sendable {
    case keep
    case removeOfflineMedia
    case removeLearningHistory
    case removeAllDeviceData
}

public protocol AuthenticationManaging: Sendable {
    var snapshots: AsyncStream<AuthenticationState> { get }
    func restore() async
    func connect(serverURL: String, username: String, password: String, keepSignedIn: Bool, allowsInsecureLocalhost: Bool) async
    func validAccessToken() async throws -> String
    func currentServer() async throws -> ServerConfiguration
    func logout(localData: LogoutLocalDataDisposition) async
}

public protocol AuthenticationAPI: Sendable {
    func bootstrap(server: ServerConfiguration) async throws -> ServerBootstrap
    func createSession(server: ServerConfiguration, username: String, password: String) async throws -> SessionTokens
    func refreshSession(server: ServerConfiguration, refreshToken: String) async throws -> SessionTokens
    func revokeSession(server: ServerConfiguration, accessToken: String) async throws
}

public protocol SessionTokenStoring: Sendable {
    func load() async throws -> SessionTokens?
    func save(_ tokens: SessionTokens) async throws
    func remove() async throws
}

public protocol ServerConfigurationStoring: Sendable {
    func load() async throws -> ServerConfiguration?
    func save(_ configuration: ServerConfiguration) async throws
    func remove() async throws
}

public protocol AccountDataClearing: Sendable {
    func clear(_ disposition: LogoutLocalDataDisposition) async throws
}
