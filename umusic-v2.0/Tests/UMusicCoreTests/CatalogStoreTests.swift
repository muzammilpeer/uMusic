import Foundation
import Testing
import UMusicData
import UMusicDomain

private let trackID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!

private func page(revision: Int64, title: String = "Morning Light", tombstone: Bool = false) -> LibraryChangePage {
    LibraryChangePage(
        schemaVersion: 1,
        libraryRevision: String(revision),
        nextCursor: "cursor-\(revision)",
        hasMore: false,
        tracks: tombstone ? [] : [CatalogTrack(id: trackID, revision: revision, title: title, artist: "Test Artist", album: "Test Album", genres: ["Ambient"], language: "en", releaseYear: 2024, durationMilliseconds: 120_000, available: true)],
        tombstones: tombstone ? [CatalogTombstone(trackID: trackID, revision: revision, deletedAt: Date())] : []
    )
}

@Test("Catalog page and cursor commit atomically")
func catalogPageCommits() async throws {
    let store = CatalogStore(inMemory: true)
    try await store.apply(page(revision: 1))
    #expect(try await store.cursor() == "cursor-1")
    let snapshot = try await store.snapshot()
    #expect(snapshot.tracks.map(\.title) == ["Morning Light"])
}

@Test("Duplicate and older revisions cannot overwrite newer metadata")
func catalogRevisionGuard() async throws {
    let store = CatalogStore(inMemory: true)
    try await store.apply(page(revision: 10, title: "Current"))
    try await store.apply(page(revision: 2, title: "Stale"))
    #expect(try await store.snapshot().tracks.first?.title == "Current")
}

@Test("Versioned song features persist and malformed vectors cannot advance sync")
func songFeaturePersistenceAndValidation() async throws {
    let store = CatalogStore(inMemory: true)
    let features = SongFeatureSnapshot(
        schemaVersion: 1,
        provider: "deterministic",
        modelVersion: "checksum-fixture-1",
        analysisRevision: 10,
        scalars: ["energy": 0.4],
        embedding: .init(encoding: "float16_le", dimension: 2, payload: Data([0, 0, 0, 0]))
    )
    let track = CatalogTrack(id: trackID, revision: 10, title: "Analyzed", artist: "Artist", album: nil, genres: [], language: nil, releaseYear: nil, durationMilliseconds: 1_000, available: true, songFeatures: features)
    try await store.apply(.init(schemaVersion: 1, libraryRevision: "10", nextCursor: "feature-cursor", hasMore: false, tracks: [track], tombstones: []))
    #expect(try await store.snapshot().tracks.first?.songFeatures == features)

    let malformed = SongFeatureSnapshot(schemaVersion: 1, provider: "deterministic", modelVersion: "bad", analysisRevision: 11, scalars: [:], embedding: .init(encoding: "float16_le", dimension: 64, payload: Data([0])))
    let invalidTrack = CatalogTrack(id: trackID, revision: 11, title: "Analyzed", artist: "Artist", album: nil, genres: [], language: nil, releaseYear: nil, durationMilliseconds: 1_000, available: true, songFeatures: malformed)
    await #expect(throws: CatalogStoreError.self) {
        try await store.apply(.init(schemaVersion: 1, libraryRevision: "11", nextCursor: "must-not-commit", hasMore: false, tracks: [invalidTrack], tombstones: []))
    }
    #expect(try await store.cursor() == "feature-cursor")
}

@Test("Tombstones hide tracks while retaining safe metadata")
func catalogTombstone() async throws {
    let store = CatalogStore(inMemory: true)
    try await store.apply(page(revision: 1))
    try await store.apply(page(revision: 2, tombstone: true))
    #expect(try await store.snapshot().tracks.isEmpty)
}

@Test("Full catalog reconciliation hides tracks absent from the server")
func fullCatalogReconciliation() async throws {
    let store = CatalogStore(inMemory: true)
    let retained = CatalogTrack(id: UUID(), revision: 1, title: "Retained", artist: "Artist", album: nil, genres: [], language: nil, releaseYear: nil, durationMilliseconds: 1_000, available: true)
    let removed = CatalogTrack(id: UUID(), revision: 1, title: "Removed", artist: "Artist", album: nil, genres: [], language: nil, releaseYear: nil, durationMilliseconds: 1_000, available: true)
    try await store.apply(.init(schemaVersion: 1, libraryRevision: "1", nextCursor: "full-1", hasMore: false, tracks: [retained, removed], tombstones: []))

    try await store.reconcileFullCatalog(serverTrackIDs: [retained.id])
    #expect(try await store.snapshot().tracks.map(\.id) == [retained.id])

    try await store.reconcileFullCatalog(serverTrackIDs: [])
    #expect(try await store.snapshot().tracks.isEmpty)
}

@Test("Local catalog search covers title, artist, and album")
func catalogSearch() async throws {
    let store = CatalogStore(inMemory: true)
    try await store.apply(page(revision: 1))
    #expect(try await store.snapshot(query: "ambient").tracks.count == 1)
    #expect(try await store.snapshot(query: "Artist").tracks.count == 1)
    #expect(try await store.snapshot(query: "Album").tracks.count == 1)
}

@Test("Malformed catalog metadata is rejected without moving the cursor")
func malformedCatalogPage() async throws {
    let store = CatalogStore(inMemory: true)
    let invalid = LibraryChangePage(schemaVersion: 1, libraryRevision: "1", nextCursor: "bad", hasMore: false, tracks: [CatalogTrack(id: UUID(), revision: 1, title: "", artist: "Artist", album: nil, genres: [], language: nil, releaseYear: nil, durationMilliseconds: nil, available: true)], tombstones: [])
    await #expect(throws: CatalogStoreError.self) { try await store.apply(invalid) }
    #expect(try await store.cursor() == nil)
}

@Test("Catalog filters compose and unknown metadata remains browsable")
func composableCatalogFilters() async throws {
    let store = CatalogStore(inMemory: true)
    let known = CatalogTrack(id: UUID(), revision: 1, title: "Shared", artist: "Artist A", album: "Album A", genres: ["Rock"], language: "en", releaseYear: 1999, durationMilliseconds: 1_000, available: true)
    let unknown = CatalogTrack(id: UUID(), revision: 1, title: "Shared", artist: "Unknown Artist", album: nil, genres: [], language: nil, releaseYear: nil, durationMilliseconds: nil, available: true)
    try await store.apply(.init(schemaVersion: 1, libraryRevision: "1", nextCursor: "filter-cursor", hasMore: false, tracks: [known, unknown], tombstones: []))
    #expect(try await store.browse(.init(text: "Shared")).count == 2)
    #expect(try await store.browse(.init(artist: "Artist A", genre: "Rock", releaseYear: 1999, language: "en")).map(\.id) == [known.id])
    let all = try await store.browse(.init())
    let restoredUnknown = all.first(where: { $0.id == unknown.id })
    #expect(restoredUnknown?.album == nil)
    #expect(restoredUnknown?.releaseYear == nil)
}

@Test("Twenty-five-thousand-track cached search remains bounded", .timeLimit(.minutes(1)))
func largeCatalogSearchBudget() async throws {
    let store = CatalogStore(inMemory: true)
    for pageIndex in 0..<50 {
        let tracks = (0..<500).map { offset in
            let number = pageIndex * 500 + offset
            return CatalogTrack(id: UUID(), revision: 1, title: number == 24_999 ? "Unique Final Track" : "Song \(number)", artist: "Artist \(number % 100)", album: "Album \(number % 250)", genres: ["Genre \(number % 20)"], language: number.isMultiple(of: 2) ? "en" : nil, releaseYear: 1980 + number % 45, durationMilliseconds: 180_000, available: true)
        }
        try await store.apply(.init(schemaVersion: 1, libraryRevision: String(pageIndex), nextCursor: "cursor-\(pageIndex)", hasMore: pageIndex < 49, tracks: tracks, tombstones: []))
    }
    let clock = ContinuousClock(); let start = clock.now
    let matches = try await store.browse(.init(text: "Unique Final"))
    let elapsed = start.duration(to: clock.now)
    #expect(matches.map(\.title) == ["Unique Final Track"])
    #expect(elapsed < .seconds(2))
}
