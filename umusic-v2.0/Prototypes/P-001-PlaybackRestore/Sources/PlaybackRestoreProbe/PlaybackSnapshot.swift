import Foundation

public struct PlaybackSnapshot: Codable, Equatable, Sendable {
    public let trackID: UUID
    public let title: String
    public let artist: String
    public let mediaURL: URL
    public let positionSeconds: Double
    public let queueTrackIDs: [UUID]

    public init(
        trackID: UUID,
        title: String,
        artist: String,
        mediaURL: URL,
        positionSeconds: Double,
        queueTrackIDs: [UUID]
    ) {
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.mediaURL = mediaURL
        self.positionSeconds = max(positionSeconds, 0)
        self.queueTrackIDs = queueTrackIDs
    }
}

public protocol PlaybackSnapshotReading: Sendable {
    func read() throws -> PlaybackSnapshot?
}

public struct JSONPlaybackSnapshotStore: PlaybackSnapshotReading, Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func read() throws -> PlaybackSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(PlaybackSnapshot.self, from: Data(contentsOf: fileURL))
    }
}

