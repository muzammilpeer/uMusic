import Foundation
import Testing
import UMusicCore
import UMusicData
import UMusicDomain
import UMusicNetworking
import UMusicSecurity
import UMusicSupport

private actor AuthenticationAPISpy: AuthenticationAPI {
    var bootstrapValue = ServerBootstrap(serverID: "test", apiVersion: "v2", schemaVersion: 1, capabilities: [.catalogSync, .audioStream], libraryCount: 10)
    var sessionValue: SessionTokens
    var refreshedValue: SessionTokens
    var error: Error?
    var refreshCount = 0
    var delayRefresh = false
    var delayBootstrap = false
    var revokeCount = 0

    init(session: SessionTokens, refreshed: SessionTokens? = nil) {
        sessionValue = session
        refreshedValue = refreshed ?? session
    }

    func bootstrap(server: ServerConfiguration) async throws -> ServerBootstrap {
        if delayBootstrap { try await Task.sleep(for: .seconds(5)) }
        if let error { throw error }
        return bootstrapValue
    }

    func createSession(server: ServerConfiguration, username: String, password: String) async throws -> SessionTokens {
        if let error { throw error }
        return sessionValue
    }

    func refreshSession(server: ServerConfiguration, refreshToken: String) async throws -> SessionTokens {
        refreshCount += 1
        if delayRefresh { try await Task.sleep(for: .milliseconds(30)) }
        if let error { throw error }
        return refreshedValue
    }

    func revokeSession(server: ServerConfiguration, accessToken: String) async throws {
        revokeCount += 1
        if let error { throw error }
    }

    func setBootstrap(_ value: ServerBootstrap) { bootstrapValue = value }
    func setError(_ value: Error?) { error = value }
    func setDelayRefresh(_ value: Bool) { delayRefresh = value }
    func setDelayBootstrap(_ value: Bool) { delayBootstrap = value }
    func refreshCalls() -> Int { refreshCount }
    func revokeCalls() -> Int { revokeCount }
}

@Test("A persisted session restores without storing a password")
func persistedSessionRestores() async throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let stored = tokens(expiresAt: now.addingTimeInterval(3_600))
    let server = try ServerURLValidator.normalize("https://music.example.com")
    let tokenStore = MemorySessionTokenStore(tokens: stored)
    let configurationStore = MemoryServerConfigurationStore(configuration: server)
    let coordinator = AuthenticationCoordinator(
        api: AuthenticationAPISpy(session: stored),
        tokenStore: tokenStore,
        configurationStore: configurationStore,
        dateProvider: FixedDateProvider(now)
    )
    var iterator = coordinator.snapshots.makeAsyncIterator()
    _ = await iterator.next()
    await coordinator.restore()
    guard case .authenticated(let user, let restoredServer, true) = await iterator.next() else {
        Issue.record("Expected restored session")
        return
    }
    #expect(user == stored.user)
    #expect(restoredServer == server)
}

@Test("Cancelling connection returns to signed out")
func connectionCancellation() async {
    let api = AuthenticationAPISpy(session: tokens(expiresAt: .distantFuture))
    await api.setDelayBootstrap(true)
    let coordinator = AuthenticationCoordinator(api: api, tokenStore: MemorySessionTokenStore())
    var iterator = coordinator.snapshots.makeAsyncIterator()
    _ = await iterator.next()
    let task = Task {
        await coordinator.connect(serverURL: "https://music.example.com", username: "u", password: "p", keepSignedIn: false, allowsInsecureLocalhost: false)
    }
    #expect(await iterator.next() == .validatingServer)
    task.cancel()
    await task.value
    #expect(await iterator.next() == .signedOut)
}

private actor DataClearerSpy: AccountDataClearing {
    var values: [LogoutLocalDataDisposition] = []
    func clear(_ disposition: LogoutLocalDataDisposition) async throws { values.append(disposition) }
    func last() -> LogoutLocalDataDisposition? { values.last }
}

private func tokens(expiresAt: Date, access: String = "access") -> SessionTokens {
    SessionTokens(
        accessToken: access,
        refreshToken: "refresh",
        expiresAt: expiresAt,
        user: AuthenticatedUser(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "Test"),
        capabilities: [.catalogSync, .audioStream]
    )
}

@Test("Server URLs normalize to HTTPS and reject unsafe forms")
func serverURLValidation() throws {
    #expect(try ServerURLValidator.normalize("music.example.com").baseURL.absoluteString == "https://music.example.com")
    #expect(throws: ServerURLValidationError.insecureTransport) { try ServerURLValidator.normalize("http://music.example.com") }
    #expect(throws: ServerURLValidationError.credentialsInURL) { try ServerURLValidator.normalize("https://user:pass@music.example.com") }
    #expect(throws: ServerURLValidationError.queryOrFragmentNotAllowed) { try ServerURLValidator.normalize("https://music.example.com?token=secret") }
    #expect(try ServerURLValidator.normalize("http://localhost:8000", allowsInsecureLocalhost: true).baseURL.scheme == "http")
}

@Test("Successful authentication persists only when requested")
func successfulAuthentication() async throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let api = AuthenticationAPISpy(session: tokens(expiresAt: now.addingTimeInterval(3_600)))
    let store = MemorySessionTokenStore()
    let coordinator = AuthenticationCoordinator(api: api, tokenStore: store, dateProvider: FixedDateProvider(now))
    var iterator = coordinator.snapshots.makeAsyncIterator()
    #expect(await iterator.next() == .signedOut)

    await coordinator.connect(serverURL: "https://music.example.com", username: "person", password: "secret", keepSignedIn: true, allowsInsecureLocalhost: false)

    #expect(await iterator.next() == .validatingServer)
    #expect(await iterator.next() == .authenticating)
    guard case .authenticated(_, _, true) = await iterator.next() else { Issue.record("Expected persisted authenticated state"); return }
    #expect(try await store.load()?.accessToken == "access")
}

@Test("Required capability mismatch fails before login")
func capabilityMismatch() async {
    let api = AuthenticationAPISpy(session: tokens(expiresAt: Date.distantFuture))
    await api.setBootstrap(ServerBootstrap(serverID: "old", apiVersion: "v2", schemaVersion: 1, capabilities: [.catalogSync], libraryCount: 0))
    let coordinator = AuthenticationCoordinator(api: api, tokenStore: MemorySessionTokenStore())
    var iterator = coordinator.snapshots.makeAsyncIterator()
    _ = await iterator.next()
    await coordinator.connect(serverURL: "https://music.example.com", username: "u", password: "p", keepSignedIn: false, allowsInsecureLocalhost: false)
    _ = await iterator.next()
    guard case .failed(let failure) = await iterator.next() else { Issue.record("Expected capability failure"); return }
    #expect(failure.code == "incompatible_server")
}

@Test("Concurrent expired-token requests share one refresh")
func refreshIsDeduplicated() async throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let api = AuthenticationAPISpy(session: tokens(expiresAt: now), refreshed: tokens(expiresAt: now.addingTimeInterval(3_600), access: "new-access"))
    await api.setDelayRefresh(true)
    let coordinator = AuthenticationCoordinator(api: api, tokenStore: MemorySessionTokenStore(), dateProvider: FixedDateProvider(now))
    await coordinator.connect(serverURL: "https://music.example.com", username: "u", password: "p", keepSignedIn: false, allowsInsecureLocalhost: false)

    try await withThrowingTaskGroup(of: String.self) { group in
        for _ in 0..<12 { group.addTask { try await coordinator.validAccessToken() } }
        for try await value in group { #expect(value == "new-access") }
    }
    #expect(await api.refreshCalls() == 1)
}

@Test("Denied secure persistence does not leave an authenticated session")
func deniedPersistenceFails() async {
    let store = MemorySessionTokenStore()
    await store.setDenyWrites(true)
    let coordinator = AuthenticationCoordinator(api: AuthenticationAPISpy(session: tokens(expiresAt: .distantFuture)), tokenStore: store)
    var iterator = coordinator.snapshots.makeAsyncIterator()
    _ = await iterator.next()
    await coordinator.connect(serverURL: "https://music.example.com", username: "u", password: "p", keepSignedIn: true, allowsInsecureLocalhost: false)
    _ = await iterator.next(); _ = await iterator.next()
    guard case .failed(let failure) = await iterator.next() else { Issue.record("Expected storage failure"); return }
    #expect(failure.code == "secure_storage_failed")
}

@Test("Logout clears the token and forwards the explicit local-data choice")
func logoutChoice() async throws {
    let store = MemorySessionTokenStore()
    let clearer = DataClearerSpy()
    let api = AuthenticationAPISpy(session: tokens(expiresAt: .distantFuture))
    let coordinator = AuthenticationCoordinator(api: api, tokenStore: store, dataClearer: clearer)
    await coordinator.connect(serverURL: "https://music.example.com", username: "u", password: "p", keepSignedIn: true, allowsInsecureLocalhost: false)
    await coordinator.logout(localData: .removeLearningHistory)
    #expect(try await store.load() == nil)
    #expect(await clearer.last() == .removeLearningHistory)
    #expect(await api.revokeCalls() == 1)
}

@Test("Offline authentication exposes a retryable redacted failure")
func offlineFailure() async {
    let api = AuthenticationAPISpy(session: tokens(expiresAt: .distantFuture))
    await api.setError(AuthenticationTransportError.offline(requestID: "req-1"))
    let coordinator = AuthenticationCoordinator(api: api, tokenStore: MemorySessionTokenStore())
    var iterator = coordinator.snapshots.makeAsyncIterator()
    _ = await iterator.next()
    await coordinator.connect(serverURL: "https://music.example.com", username: "u", password: "secret", keepSignedIn: false, allowsInsecureLocalhost: false)
    _ = await iterator.next()
    guard case .offline(let failure) = await iterator.next() else { Issue.record("Expected offline state"); return }
    #expect(failure.retryable)
    #expect(failure.requestID == "req-1")
    #expect(!failure.message.contains("secret"))
}
