import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var token: String?
    @Published var serverText: String
    @Published var errorMessage: String?
    @Published private(set) var deviceID: UUID?

    let api: any MusicAPI
    let credentials: any CredentialStore

    init(
        api: any MusicAPI = APIClient(),
        credentials: any CredentialStore = KeychainStore(),
        defaults: UserDefaults = .standard
    ) {
        self.api = api
        self.credentials = credentials
        let savedServer = defaults.string(forKey: "serverURL")
        serverText = Self.initialServer(savedServer)
        token = try? credentials.loadToken()
        deviceID = defaults.string(forKey: "deviceID").flatMap(UUID.init(uuidString:))
    }

    var server: URL? {
        guard let url = URL(string: serverText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || isLocalDevelopment(url)
        else { return nil }
        return url
    }

    func signIn(username: String, password: String, deviceName: String) async {
        guard let server else { errorMessage = APIError.invalidServer.localizedDescription; return }
        do {
            let response = try await api.login(
                server: server, username: username, password: password, deviceName: deviceName
            )
            try credentials.save(token: response.token)
            UserDefaults.standard.set(server.absoluteString, forKey: "serverURL")
            UserDefaults.standard.set(response.device.id.uuidString, forKey: "deviceID")
            deviceID = response.device.id
            token = response.token
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut(message: String? = nil) {
        try? credentials.deleteToken()
        token = nil
        deviceID = nil
        UserDefaults.standard.removeObject(forKey: "deviceID")
        errorMessage = message
    }

    func refreshDeviceIdentity() async {
        guard let server, let token else { return }
        do {
            let current = try await api.currentSession(server: server, token: token)
            deviceID = current.device.id
            UserDefaults.standard.set(current.device.id.uuidString, forKey: "deviceID")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isLocalDevelopment(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http", let host = url.host else { return false }
        return host == "localhost" || host == "127.0.0.1" || host.hasPrefix("192.168.")
            || host.hasPrefix("10.")
    }

    private static func initialServer(_ saved: String?) -> String {
        guard let saved, let url = URL(string: saved), let host = url.host else {
            return AppConfiguration.productionServer.absoluteString
        }
        let retired = host == "192.168.1.64" || host == "192.168.1.67"
            || host == "music.example.com"
        return retired ? AppConfiguration.productionServer.absoluteString : saved
    }
}
