import Observation
import Foundation

@MainActor
@Observable
public final class AppNavigationModel {
    public var selectedTab: AppTab = .home
    public var homePath: [AppRoute] = []
    public var libraryPath: [AppRoute] = []
    public var nowPath: [AppRoute] = []
    public var searchPath: [AppRoute] = []
    public var presentedSheet: SheetRoute?
    public var searchQuery = ""

    public init() {}

    public func restorationData() -> Data {
        (try? JSONEncoder().encode(Restoration(selectedTab: selectedTab, homePath: homePath, libraryPath: libraryPath, nowPath: nowPath, searchPath: searchPath, searchQuery: String(searchQuery.prefix(512))))) ?? Data()
    }

    public func restore(from data: Data) {
        guard data.count <= 65_536, let value = try? JSONDecoder().decode(Restoration.self, from: data) else { return }
        selectedTab = value.selectedTab; homePath = Array(value.homePath.prefix(32)); libraryPath = Array(value.libraryPath.prefix(32)); nowPath = Array(value.nowPath.prefix(32)); searchPath = Array(value.searchPath.prefix(32)); searchQuery = String(value.searchQuery.prefix(512))
    }

    private struct Restoration: Codable {
        let selectedTab: AppTab; let homePath: [AppRoute]; let libraryPath: [AppRoute]; let nowPath: [AppRoute]; let searchPath: [AppRoute]; let searchQuery: String
    }

    @discardableResult public func open(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "umusic" else { return false }
        let kind = url.host?.lowercased()
        let value = url.pathComponents.dropFirst().first
        selectedTab = kind == "search" ? .search : .library
        switch kind {
        case "track":
            guard let value, let id = UUID(uuidString: value) else { return false }
            libraryPath.append(.track(id)); return true
        case "playlist":
            guard let value, let id = UUID(uuidString: value) else { return false }
            libraryPath.append(.playlist(id)); return true
        case "search":
            searchQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            return true
        default: return false
        }
    }
}
