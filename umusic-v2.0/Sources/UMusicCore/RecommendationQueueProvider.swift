import Foundation
import UMusicDomain

public actor RecommendationQueueProvider: AutomaticQueueProviding {
    private let library: any LibraryProviding
    private let personalization: any PersonalizationManaging
    private let offline: any OfflineManaging

    public init(library: any LibraryProviding, personalization: any PersonalizationManaging, offline: any OfflineManaging) {
        self.library = library; self.personalization = personalization; self.offline = offline
    }

    public func automaticTracks(excluding trackIDs: Set<UUID>, count: Int, at date: Date) async -> [TrackSummary] {
        guard count > 0, let tracks = try? await library.browse(LibraryQuery()), !tracks.isEmpty else { return [] }
        let offlineIDs = Set((await offline.storageSnapshot()).entries.filter { $0.state == .ready }.map(\.trackID))
        let result = await personalization.recommendations(from: tracks, at: date, offlineTrackIDs: offlineIDs, excluding: trackIDs, limit: count)
        return result.items.map(\.track)
    }
}

