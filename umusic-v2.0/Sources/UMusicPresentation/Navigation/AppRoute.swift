import Foundation

public enum AppTab: String, CaseIterable, Hashable, Codable, Sendable {
    case home
    case library
    case now
    case search
}

public enum AppRoute: Hashable, Codable, Sendable {
    case track(UUID)
    case album(UUID)
    case artist(UUID)
    case playlist(UUID)
    case importJob(UUID)
    case settings(SettingsRoute)
}

public enum SettingsRoute: String, Hashable, Codable, Sendable {
    case account
    case playback
    case offlineStorage
    case personalization
    case activityAndSensors
    case privacyAndRetention
    case appearance
    case exportAndDiagnostics
    case about
}

public enum SheetRoute: Hashable, Identifiable, Sendable {
    case settings(SettingsRoute)
    case queue
    case activity

    public var id: String { String(describing: self) }
}

public enum PlayerRoute: Hashable, Sendable {
    case compact
    case full
    case queue
    case visualizer
}
