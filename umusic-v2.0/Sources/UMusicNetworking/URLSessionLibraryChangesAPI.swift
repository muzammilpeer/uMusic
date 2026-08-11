import Foundation
import UMusicDomain

public struct URLSessionLibraryChangesAPI: LibraryChangesAPI {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func changes(server: ServerConfiguration, accessToken: String, cursor: String?, limit: Int) async throws -> LibraryChangePage {
        var components = URLComponents(url: server.baseURL.appending(path: "api/v2/library/changes"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 500)))]
        if let cursor { components.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LibraryChangesTransportError.unsuccessfulResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try Self.decoder.decode(WirePage.self, from: data).domain
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            guard let date = ISO8601DateFormatter().date(from: value) else {
                throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid date")
            }
            return date
        }
        return decoder
    }()
}

public enum LibraryChangesTransportError: Error, Equatable {
    case unsuccessfulResponse(statusCode: Int)
}

private struct WirePage: Decodable {
    let schemaVersion: Int
    let libraryRevision: String
    let nextCursor: String
    let hasMore: Bool
    let tracks: [WireTrack]
    let tombstones: [WireTombstone]
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", libraryRevision = "library_revision", nextCursor = "next_cursor", hasMore = "has_more", tracks, tombstones }
    var domain: LibraryChangePage { .init(schemaVersion: schemaVersion, libraryRevision: libraryRevision, nextCursor: nextCursor, hasMore: hasMore, tracks: tracks.map(\.domain), tombstones: tombstones.map(\.domain)) }
}

private struct WireTrack: Decodable {
    struct Artist: Decodable { let name: String }
    struct Album: Decodable { let title: String }
    struct Classification: Decodable { let category: String; let confidence: Double }
    struct SongFeatures: Decodable {
        struct Embedding: Decodable { let encoding: String; let dimension: Int; let payload: Data }
        let schemaVersion: Int; let provider: String; let modelVersion: String; let analysisRevision: Int64
        let scalars: [String: Double]; let embedding: Embedding
        enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", provider, modelVersion = "model_version", analysisRevision = "analysis_revision", scalars, embedding }
        var domain: SongFeatureSnapshot { .init(schemaVersion: schemaVersion, provider: provider, modelVersion: modelVersion, analysisRevision: analysisRevision, scalars: scalars, embedding: .init(encoding: embedding.encoding, dimension: embedding.dimension, payload: embedding.payload)) }
    }
    let id: UUID; let revision: Int64; let title: String; let artists: [Artist]; let album: Album?
    let genres: [String]; let language: String?; let releaseYear: Int?; let durationMilliseconds: Int64?; let available: Bool; let contentClassifications: [Classification]?; let songFeatures: SongFeatures?
    enum CodingKeys: String, CodingKey { case id, revision, title, artists, album, genres, language, releaseYear = "release_year", durationMilliseconds = "duration_ms", available, contentClassifications = "content_classifications", songFeatures = "song_features" }
    var domain: CatalogTrack { .init(id: id, revision: revision, title: title, artist: artists.map(\.name).joined(separator: ", "), album: album?.title, genres: genres, language: language, releaseYear: releaseYear, durationMilliseconds: durationMilliseconds, available: available, contentClassifications: contentClassifications?.compactMap { classification in ContentCategory(rawValue: classification.category).map { .init(category: $0, confidence: classification.confidence) } }, songFeatures: songFeatures?.domain) }
}

private struct WireTombstone: Decodable {
    let trackID: UUID; let revision: Int64; let deletedAt: Date
    enum CodingKeys: String, CodingKey { case trackID = "track_id", revision, deletedAt = "deleted_at" }
    var domain: CatalogTombstone { .init(trackID: trackID, revision: revision, deletedAt: deletedAt) }
}
