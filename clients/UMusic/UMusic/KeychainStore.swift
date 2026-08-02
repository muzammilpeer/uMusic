import Foundation
import Security

protocol CredentialStore: Sendable {
    func save(token: String) throws
    func loadToken() throws -> String?
    func deleteToken() throws
}

struct KeychainStore: CredentialStore {
    private let service = "app.umusic.client"
    private let account = "device-token"

    func save(token: String) throws {
        try deleteToken()
        let status = SecItemAdd(primaryQuery.merging([
            kSecClass: kSecClassGenericPassword,
            kSecValueData: Data(token.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]) { _, new in new } as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    func loadToken() throws -> String? {
        if let token = try load(query: primaryQuery) { return token }

        // Migrate installations that stored the token before the Share Extension
        // introduced a shared keychain access group.
        guard let token = try load(query: legacyQuery) else { return nil }
        try save(token: token)
        return token
    }

    private func load(query: [CFString: Any]) throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query.merging([
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]) { _, new in new } as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status) }
        return String(data: data, encoding: .utf8)
    }

    func deleteToken() throws {
        let primaryStatus = SecItemDelete(primaryQuery as CFDictionary)
        guard primaryStatus == errSecSuccess || primaryStatus == errSecItemNotFound else {
            throw KeychainError(primaryStatus)
        }
        let legacyStatus = SecItemDelete(legacyQuery as CFDictionary)
        guard legacyStatus == errSecSuccess || legacyStatus == errSecItemNotFound else {
            throw KeychainError(legacyStatus)
        }
    }

    private var legacyQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    private var primaryQuery: [CFString: Any] {
        sharedQuery
    }

    private var sharedQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: "3S2DR3CGY4.app.umusic.shared",
        ]
    }
}

struct KeychainError: Error { let status: OSStatus; init(_ status: OSStatus) { self.status = status } }
