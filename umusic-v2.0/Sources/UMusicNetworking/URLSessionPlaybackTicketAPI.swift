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
            let status = (response as? HTTPURLResponse)?.statusCode
            let code = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.code
            let responsePreview = String(data: data.prefix(300), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PlaybackTicketTransportError.unsuccessfulResponse(
                status: status,
                code: code,
                responsePreview: responsePreview
            )
        }
        return try Self.decoder.decode(ResponseBody.self, from: data).tickets
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            guard let date = ISO8601DateFormatter().date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date")
            }
            return date
        }
        return decoder
    }()
}

public enum PlaybackTicketTransportError: Error, LocalizedError {
    case unsuccessfulResponse(status: Int?, code: String?, responsePreview: String?)

    public var errorDescription: String? {
        switch self {
        case .unsuccessfulResponse(let status, let code, let responsePreview):
            let statusText = status.map(String.init) ?? "unknown"
            let preview = responsePreview.flatMap { $0.isEmpty ? nil : $0 } ?? "empty response body"
            return "Media ticket request failed (HTTP \(statusText), \(code ?? "no server code")): \(preview)"
        }
    }
}
private struct RequestBody: Encodable { let trackIDs: [UUID]; enum CodingKeys: String, CodingKey { case trackIDs = "track_ids" } }
private struct ResponseBody: Decodable { let tickets: [PlaybackTicket] }
private struct ErrorBody: Decodable { let code: String }
