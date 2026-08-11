import Foundation

public struct SongFeatureSnapshot: Codable, Equatable, Hashable, Sendable {
    public struct Embedding: Codable, Equatable, Hashable, Sendable {
        public let encoding: String
        public let dimension: Int
        public let payload: Data
        public init(encoding: String, dimension: Int, payload: Data) {
            self.encoding = encoding; self.dimension = dimension; self.payload = payload
        }
    }

    public let schemaVersion: Int
    public let provider: String
    public let modelVersion: String
    public let analysisRevision: Int64
    public let scalars: [String: Double]
    public let embedding: Embedding

    public init(schemaVersion: Int, provider: String, modelVersion: String, analysisRevision: Int64, scalars: [String: Double], embedding: Embedding) {
        self.schemaVersion = schemaVersion; self.provider = provider; self.modelVersion = modelVersion
        self.analysisRevision = analysisRevision; self.scalars = scalars; self.embedding = embedding
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(schemaVersion); hasher.combine(provider); hasher.combine(modelVersion)
        hasher.combine(analysisRevision); hasher.combine(embedding)
        for key in scalars.keys.sorted() { hasher.combine(key); hasher.combine(scalars[key]) }
    }
}

public struct CatalogTrack: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let revision: Int64
    public let title: String
    public let artist: String
    public let album: String?
    public let genres: [String]
    public let language: String?
    public let releaseYear: Int?
    public let durationMilliseconds: Int64?
    public let available: Bool
    public let contentClassifications: [ContentClassification]?
    public let songFeatures: SongFeatureSnapshot?

    public init(id: UUID, revision: Int64, title: String, artist: String, album: String?, genres: [String], language: String?, releaseYear: Int?, durationMilliseconds: Int64?, available: Bool, contentClassifications: [ContentClassification]? = nil, songFeatures: SongFeatureSnapshot? = nil) {
        self.id = id
        self.revision = revision
        self.title = title
        self.artist = artist
        self.album = album
        self.genres = genres
        self.language = language
        self.releaseYear = releaseYear
        self.durationMilliseconds = durationMilliseconds
        self.available = available
        self.contentClassifications = contentClassifications
        self.songFeatures = songFeatures
    }
}

public struct CatalogTombstone: Codable, Equatable, Sendable {
    public let trackID: UUID
    public let revision: Int64
    public let deletedAt: Date

    public init(trackID: UUID, revision: Int64, deletedAt: Date) {
        self.trackID = trackID
        self.revision = revision
        self.deletedAt = deletedAt
    }
}

public struct LibraryChangePage: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let libraryRevision: String
    public let nextCursor: String
    public let hasMore: Bool
    public let tracks: [CatalogTrack]
    public let tombstones: [CatalogTombstone]

    public init(schemaVersion: Int, libraryRevision: String, nextCursor: String, hasMore: Bool, tracks: [CatalogTrack], tombstones: [CatalogTombstone]) {
        self.schemaVersion = schemaVersion
        self.libraryRevision = libraryRevision
        self.nextCursor = nextCursor
        self.hasMore = hasMore
        self.tracks = tracks
        self.tombstones = tombstones
    }
}

public protocol LibraryChangesAPI: Sendable {
    func changes(server: ServerConfiguration, accessToken: String, cursor: String?, limit: Int) async throws -> LibraryChangePage
}
