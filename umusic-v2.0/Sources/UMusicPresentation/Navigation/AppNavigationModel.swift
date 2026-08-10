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
