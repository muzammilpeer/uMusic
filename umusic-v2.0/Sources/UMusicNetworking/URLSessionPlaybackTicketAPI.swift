import Foundation
import UMusicDomain

public struct URLSessionPlaybackTicketAPI: PlaybackTicketAPI {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func tickets(server: ServerConfiguration, accessToken: String, trackIDs: [UUID]) async throws -> [PlaybackTicket] {
        var request = URLRequest(url: server.baseURL.appending(path: "api/v2/media/playback-tickets"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(RequestBody(trackIDs: trackIDs))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PlaybackTicketTransportError.unsuccessfulResponse
        }
        return try Self.decoder.decode(ResponseBody.self, from: data).tickets
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public enum PlaybackTicketTransportError: Error { case unsuccessfulResponse }
private struct RequestBody: Encodable { let trackIDs: [UUID]; enum CodingKeys: String, CodingKey { case trackIDs = "track_ids" } }
private struct ResponseBody: Decodable { let tickets: [PlaybackTicket] }
