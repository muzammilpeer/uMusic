import Foundation
import Security

public struct ImportCredentials: Codable, Equatable, Sendable {
    public let server: URL
    public let accessToken: String
    public init(server: URL, accessToken: String) { self.server = server; self.accessToken = accessToken }
}

public protocol ImportCredentialStoring: Sendable {
    func load() async throws -> ImportCredentials?
    func save(_ credentials: ImportCredentials) async throws
    func remove() async throws
}

public actor SharedKeychainImportCredentialStore: ImportCredentialStoring {
    private let service: String
    private let account: String
    private let accessGroup: String
    public init(accessGroup: String, service: String = "app.umusic.v2.import", account: String = "current") {
        self.accessGroup = accessGroup; self.service = service; self.account = account
    }
    public func load() throws -> ImportCredentials? {
        var query = baseQuery; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ImportClientError.authenticationUnavailable }
        guard let value = try? JSONDecoder().decode(ImportCredentials.self, from: data) else { throw ImportClientError.authenticationUnavailable }
        return value
    }
    public func save(_ credentials: ImportCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ImportClientError.authenticationUnavailable }
        } else if status != errSecSuccess { throw ImportClientError.authenticationUnavailable }
    }
    public func remove() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ImportClientError.authenticationUnavailable }
    }
    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecAttrAccessGroup as String: accessGroup]
    }
}

public enum SharedCredentialMigration {
    @discardableResult public static func migrateIfNeeded(from legacy: any ImportCredentialStoring, to shared: any ImportCredentialStoring) async throws -> Bool {
        if try await shared.load() != nil { return false }
        guard let credentials = try await legacy.load() else { return false }
        try await shared.save(credentials)
        return true
    }
}

public actor MemoryImportCredentialStore: ImportCredentialStoring {
    private var value: ImportCredentials?
    public init(_ value: ImportCredentials? = nil) { self.value = value }
    public func load() -> ImportCredentials? { value }
    public func save(_ credentials: ImportCredentials) { value = credentials }
    public func remove() { value = nil }
}
