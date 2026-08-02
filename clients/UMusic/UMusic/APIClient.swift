import Foundation

enum APIError: LocalizedError, Equatable {
    case invalidServer
    case unauthorized
    case server(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidServer: "Enter a valid HTTPS server URL."
        case .unauthorized: "This device is no longer authorized. Sign in again."
        case let .server(code): "The server returned HTTP \(code)."
        case .invalidResponse: "The server response could not be read."
        }
    }
}

protocol MusicAPI: Sendable {
    func login(server: URL, username: String, password: String, deviceName: String) async throws
        -> LoginResponse
    func tracks(server: URL, token: String, query: String) async throws -> Page<Track>
    func playlists(server: URL, token: String) async throws -> [Playlist]
    func currentSession(server: URL, token: String) async throws -> CurrentSessionResponse
    func deleteTrack(server: URL, token: String, trackID: UUID) async throws
    func upload(server: URL, token: String, events: [ListeningEvent]) async throws
}

protocol RemoteImportAPI: Sendable {
    func createRemoteImport(server: URL, token: String, urls: String, attested: Bool) async throws
        -> RemoteImportJob
    func remoteImport(server: URL, token: String, jobID: UUID) async throws -> RemoteImportJob
}

struct APIClient: MusicAPI, RemoteImportAPI {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func login(server: URL, username: String, password: String, deviceName: String) async throws
        -> LoginResponse
    {
        var request = URLRequest(url: server.appending(path: "api/v1/auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "username": username,
            "password": password,
            "device_name": deviceName,
            "platform": platformName,
        ])
        return try await send(request, as: LoginResponse.self)
    }

    func tracks(server: URL, token: String, query: String) async throws -> Page<Track> {
        var components = URLComponents(
            url: server.appending(path: "api/v1/tracks"), resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = [URLQueryItem(name: "q", value: query)] }
        guard let url = components?.url else { throw APIError.invalidServer }
        return try await send(authorized(url, token: token), as: Page<Track>.self)
    }

    func track(server: URL, token: String, trackID: UUID) async throws -> Track {
        try await send(
            authorized(server.appending(path: "api/v1/tracks/\(trackID.uuidString.lowercased())"), token: token),
            as: Track.self
        )
    }

    func playlists(server: URL, token: String) async throws -> [Playlist] {
        try await send(
            authorized(server.appending(path: "api/v1/playlists/"), token: token),
            as: [Playlist].self
        )
    }

    func currentSession(server: URL, token: String) async throws -> CurrentSessionResponse {
        try await send(
            authorized(server.appending(path: "api/v1/me"), token: token),
            as: CurrentSessionResponse.self
        )
    }

    func deleteTrack(server: URL, token: String, trackID: UUID) async throws {
        var request = authorized(
            server.appending(path: "api/v1/tracks/\(trackID.uuidString.lowercased())"), token: token
        )
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw APIError.unauthorized }
        guard http.statusCode == 204 else { throw APIError.server(http.statusCode) }
    }

    func updatePlaylist(
        server: URL, token: String, playlistID: UUID, trackIDs: [UUID]
    ) async throws -> Playlist {
        var request = authorized(
            server.appending(path: "api/v1/playlists/\(playlistID.uuidString.lowercased())/"), token: token
        )
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "track_ids": trackIDs.map(\.uuidString)
        ])
        return try await send(request, as: Playlist.self)
    }

    func upload(server: URL, token: String, events: [ListeningEvent]) async throws {
        var request = authorized(server.appending(path: "api/v1/events/batch/"), token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.uMusic.encode(EventBatch(events: events))
        let _: EventBatchResponse = try await send(request, as: EventBatchResponse.self)
    }

    func createRemoteImport(
        server: URL, token: String, urls: String, attested: Bool
    ) async throws -> RemoteImportJob {
        var request = authorized(
            server.appending(path: "api/v1/adapters/remote/"), token: token
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "urls": urls,
            "attested": attested,
        ])
        return try await send(request, as: RemoteImportJob.self)
    }

    func remoteImport(server: URL, token: String, jobID: UUID) async throws
        -> RemoteImportJob
    {
        try await send(
            authorized(
                server.appending(path: "api/v1/adapters/jobs/\(jobID.uuidString.lowercased())/"),
                token: token
            ),
            as: RemoteImportJob.self
        )
    }

    private func authorized(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server(http.statusCode) }
        do { return try JSONDecoder.uMusic.decode(T.self, from: data) }
        catch { throw APIError.invalidResponse }
    }

    private var platformName: String {
        #if os(macOS)
        "macos"
        #else
        "ios"
        #endif
    }
}

private struct EventBatchResponse: Codable { let accepted: Int; let duplicates: Int }
