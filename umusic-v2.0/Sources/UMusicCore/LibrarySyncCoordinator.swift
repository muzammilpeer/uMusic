import Foundation
import UMusicData
import UMusicDomain

public actor LibrarySyncCoordinator: LibraryProviding {
    public nonisolated let snapshots: AsyncStream<LibrarySnapshot>
    private let continuation: AsyncStream<LibrarySnapshot>.Continuation
    private let store: CatalogStore
    private let api: any LibraryChangesAPI
    private let authentication: any AuthenticationManaging
    private var syncing = false

    public init(store: CatalogStore, api: any LibraryChangesAPI, authentication: any AuthenticationManaging) {
        self.store = store
        self.api = api
        self.authentication = authentication
        let stream = AsyncStream<LibrarySnapshot>.makeStream()
        snapshots = stream.stream
        continuation = stream.continuation
        Task { [store, continuation] in
            continuation.yield((try? await store.snapshot()) ?? .empty)
        }
    }

    deinit { continuation.finish() }

    public func sync() async throws {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        let cached = try await store.snapshot()
        continuation.yield(.init(tracks: cached.tracks, lastSyncAt: cached.lastSyncAt, isSyncing: true))
        do {
            let server = try await authentication.currentServer()
            let token = try await authentication.validAccessToken()
            // A user-initiated Sync is authoritative. Always start from the beginning so
            // a server-side reset can also remove locally cached catalog rows even when
            // the server no longer has tombstones for those tracks.
            var cursor: String?
            var pages: [LibraryChangePage] = []
            var serverTrackIDs = Set<UUID>()
            repeat {
                try Task.checkCancellation()
                let page = try await api.changes(server: server, accessToken: token, cursor: cursor, limit: 500)
                pages.append(page)
                serverTrackIDs.formUnion(page.tracks.lazy.filter(\.available).map(\.id))
                cursor = page.nextCursor
                if !page.hasMore { break }
            } while true

            // Do not mutate the local catalog until every page has arrived. A failed or
            // interrupted refresh therefore leaves the last usable library untouched.
            for page in pages {
                try await store.apply(page)
            }
            try await store.reconcileFullCatalog(serverTrackIDs: serverTrackIDs)
            continuation.yield(try await store.snapshot())
        } catch {
            continuation.yield(cached)
            throw error
        }
    }

    public func browse(_ query: LibraryQuery) async throws -> [TrackSummary] {
        try await store.browse(query)
    }
}
