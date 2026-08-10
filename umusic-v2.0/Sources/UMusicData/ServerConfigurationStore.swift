import Foundation
import UMusicDomain

public actor UserDefaultsServerConfigurationStore: ServerConfigurationStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(suiteName: String? = nil, key: String = "umusic.v2.server-configuration") {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.key = key
    }

    public func load() async throws -> ServerConfiguration? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(ServerConfiguration.self, from: data)
    }

    public func save(_ configuration: ServerConfiguration) async throws {
        defaults.set(try JSONEncoder().encode(configuration), forKey: key)
    }

    public func remove() async throws { defaults.removeObject(forKey: key) }
}

public actor MemoryServerConfigurationStore: ServerConfigurationStoring {
    private var configuration: ServerConfiguration?
    public init(configuration: ServerConfiguration? = nil) { self.configuration = configuration }
    public func load() async throws -> ServerConfiguration? { configuration }
    public func save(_ configuration: ServerConfiguration) async throws { self.configuration = configuration }
    public func remove() async throws { configuration = nil }
}
