import Foundation
import Security
import UMusicDomain

public enum SessionTokenStoreError: Error, Equatable, Sendable {
    case keychain(OSStatus)
    case corruptValue
}

public actor KeychainSessionTokenStore: SessionTokenStoring {
    private let service: String
    private let account: String
    private let accessGroup: String?

    public init(service: String = "app.umusic.v2.session", account: String = "current", accessGroup: String? = nil) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    public func load() async throws -> SessionTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SessionTokenStoreError.keychain(status) }
        guard let data = result as? Data, let tokens = try? decoder.decode(SessionTokens.self, from: data) else {
            throw SessionTokenStoreError.corruptValue
        }
        return tokens
    }

    public func save(_ tokens: SessionTokens) async throws {
        let data = try encoder.encode(tokens)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let update = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let add = SecItemAdd(item as CFDictionary, nil)
            guard add == errSecSuccess else { throw SessionTokenStoreError.keychain(add) }
        } else if update != errSecSuccess {
            throw SessionTokenStoreError.keychain(update)
        }
    }

    public func remove() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SessionTokenStoreError.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    private var encoder: JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value }
    private var decoder: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
}

public actor MemorySessionTokenStore: SessionTokenStoring {
    public enum Failure: Error { case denied }
    private var tokens: SessionTokens?
    public var denyWrites = false
    public init(tokens: SessionTokens? = nil) { self.tokens = tokens }
    public func setDenyWrites(_ value: Bool) { denyWrites = value }
    public func load() async throws -> SessionTokens? { tokens }
    public func save(_ tokens: SessionTokens) async throws { if denyWrites { throw Failure.denied }; self.tokens = tokens }
    public func remove() async throws { tokens = nil }
}
