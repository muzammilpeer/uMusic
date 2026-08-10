import Foundation
import UMusicDomain
import UMusicData
import UMusicNetworking
import UMusicSupport

public actor AuthenticationCoordinator: AuthenticationManaging {
    public nonisolated let snapshots: AsyncStream<AuthenticationState>

    private let continuation: AsyncStream<AuthenticationState>.Continuation
    private let api: any AuthenticationAPI
    private let tokenStore: any SessionTokenStoring
    private let configurationStore: any ServerConfigurationStoring
    private let dataClearer: any AccountDataClearing
    private let dateProvider: any DateProviding
    private let logger: any RedactedLogging
    private let requiredCapabilities: Set<ServerCapability>
    private var state: AuthenticationState = .signedOut
    private var server: ServerConfiguration?
    private var tokens: SessionTokens?
    private var keepSignedIn = false
    private var refreshTask: Task<SessionTokens, Error>?

    public init(
        api: any AuthenticationAPI,
        tokenStore: any SessionTokenStoring,
        configurationStore: any ServerConfigurationStoring = MemoryServerConfigurationStore(),
        dataClearer: any AccountDataClearing = NoopAccountDataClearer(),
        dateProvider: any DateProviding = SystemDateProvider(),
        logger: any RedactedLogging = RedactedLogger(category: "authentication"),
        requiredCapabilities: Set<ServerCapability> = [.catalogSync, .audioStream]
    ) {
        self.api = api
        self.tokenStore = tokenStore
        self.configurationStore = configurationStore
        self.dataClearer = dataClearer
        self.dateProvider = dateProvider
        self.logger = logger
        self.requiredCapabilities = requiredCapabilities
        let stream = AsyncStream<AuthenticationState>.makeStream()
        snapshots = stream.stream
        continuation = stream.continuation
        continuation.yield(.signedOut)
    }

    deinit { continuation.finish() }

    public func restore() async {
        do {
            guard let configuration = try await configurationStore.load(), let storedTokens = try await tokenStore.load() else {
                transition(to: .signedOut)
                return
            }
            server = configuration
            tokens = storedTokens
            keepSignedIn = true
            if storedTokens.expiresAt.timeIntervalSince(dateProvider.now()) > 30 {
                transition(to: .authenticated(user: storedTokens.user, server: configuration, persistsSession: true))
            } else {
                _ = try await validAccessToken()
            }
        } catch {
            transition(to: state(for: error))
        }
    }

    public func connect(serverURL: String, username: String, password: String, keepSignedIn: Bool, allowsInsecureLocalhost: Bool = false) async {
        do {
            let configuration = try ServerURLValidator.normalize(serverURL, allowsInsecureLocalhost: allowsInsecureLocalhost)
            transition(to: .validatingServer)
            let bootstrap = try await api.bootstrap(server: configuration)
            guard bootstrap.apiVersion == "v2", requiredCapabilities.isSubset(of: bootstrap.capabilities) else {
                throw AuthenticationTransportError.incompatibleServer
            }

            try Task.checkCancellation()
            transition(to: .authenticating)
            let newTokens = try await api.createSession(server: configuration, username: username, password: password)
            guard requiredCapabilities.isSubset(of: newTokens.capabilities) else {
                throw AuthenticationTransportError.incompatibleServer
            }
            if keepSignedIn {
                do {
                    try await tokenStore.save(newTokens)
                    try await configurationStore.save(configuration)
                } catch {
                    try? await tokenStore.remove()
                    try? await configurationStore.remove()
                    throw AuthenticationCoordinatorError.secureStorage
                }
            } else {
                try? await tokenStore.remove()
                try? await configurationStore.remove()
            }

            self.server = configuration
            self.tokens = newTokens
            self.keepSignedIn = keepSignedIn
            transition(to: .authenticated(user: newTokens.user, server: configuration, persistsSession: keepSignedIn))
            logger.info("authentication_succeeded", fields: [LogField("user_id", newTokens.user.id.uuidString, privacy: .sensitive)])
        } catch is CancellationError {
            transition(to: .signedOut)
        } catch {
            tokens = nil
            try? await tokenStore.remove()
            transition(to: state(for: error))
        }
    }

    public func validAccessToken() async throws -> String {
        guard let tokens, let server else {
            transition(to: .expired)
            throw AuthenticationCoordinatorError.noSession
        }
        if tokens.expiresAt.timeIntervalSince(dateProvider.now()) > 30 { return tokens.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }

        let api = self.api
        let task = Task { try await api.refreshSession(server: server, refreshToken: tokens.refreshToken) }
        refreshTask = task
        do {
            let refreshed = try await task.value
            refreshTask = nil
            self.tokens = refreshed
            if keepSignedIn { try await tokenStore.save(refreshed) }
            transition(to: .authenticated(user: refreshed.user, server: server, persistsSession: keepSignedIn))
            return refreshed.accessToken
        } catch {
            refreshTask = nil
            switch error {
            case AuthenticationTransportError.revoked:
                self.tokens = nil
                try? await tokenStore.remove()
                transition(to: .revoked)
            case AuthenticationTransportError.unauthorized:
                self.tokens = nil
                try? await tokenStore.remove()
                transition(to: .expired)
            default:
                transition(to: state(for: error))
            }
            throw error
        }
    }

    public func currentServer() async throws -> ServerConfiguration {
        guard let server else { throw AuthenticationCoordinatorError.noSession }
        return server
    }

    public func logout(localData: LogoutLocalDataDisposition) async {
        refreshTask?.cancel()
        refreshTask = nil
        if let tokens, let server {
            try? await api.revokeSession(server: server, accessToken: tokens.accessToken)
        }
        tokens = nil
        server = nil
        keepSignedIn = false
        do {
            try await tokenStore.remove()
            try await configurationStore.remove()
            try await dataClearer.clear(localData)
            transition(to: .signedOut)
        } catch {
            transition(to: .failed(.init(code: "logout_cleanup_failed", message: "Some local data could not be removed.", retryable: true)))
        }
    }

    private func transition(to newState: AuthenticationState) {
        state = newState
        continuation.yield(newState)
    }

    private func state(for error: Error) -> AuthenticationState {
        let failure: AuthenticationFailure
        switch error {
        case AuthenticationTransportError.offline(let requestID):
            failure = .init(code: "offline", message: "The server could not be reached.", retryable: true, requestID: requestID)
            return .offline(failure)
        case AuthenticationTransportError.unauthorized(let requestID):
            failure = .init(code: "invalid_credentials", message: "The username or password was not accepted.", retryable: true, requestID: requestID)
        case AuthenticationTransportError.revoked(let requestID):
            _ = requestID
            return .revoked
        case AuthenticationTransportError.incompatibleServer:
            failure = .init(code: "incompatible_server", message: "This server does not provide the required uMusic v2 capabilities.", retryable: false)
        case AuthenticationTransportError.server(let code, let retryable, let requestID):
            failure = .init(code: code, message: "The server could not complete authentication.", retryable: retryable, requestID: requestID)
        case ServerURLValidationError.insecureTransport:
            failure = .init(code: "https_required", message: "Use an HTTPS server URL.", retryable: false)
        case AuthenticationCoordinatorError.secureStorage:
            failure = .init(code: "secure_storage_failed", message: "The session could not be saved securely.", retryable: true)
        default:
            failure = .init(code: "authentication_failed", message: "Authentication could not be completed.", retryable: true)
        }
        logger.error("authentication_failed", fields: [LogField("code", failure.code, privacy: .safe)])
        return .failed(failure)
    }
}

public enum AuthenticationCoordinatorError: Error { case noSession; case secureStorage }

public actor NoopAccountDataClearer: AccountDataClearing {
    public init() {}
    public func clear(_ disposition: LogoutLocalDataDisposition) async throws {}
}
