import Foundation
import Testing
import UMusicCore
import UMusicData
import UMusicDomain

private actor CalendarLibraryStub: LibraryProviding {
    nonisolated let snapshots: AsyncStream<LibrarySnapshot>
    let tracks: [TrackSummary]
    init(_ tracks: [TrackSummary]) { self.tracks = tracks; snapshots = AsyncStream { $0.finish() } }
    func sync() async throws {}
    func browse(_ query: LibraryQuery) async throws -> [TrackSummary] { tracks }
}

private func calendarFixture(_ tracks: [TrackSummary] = []) -> (CalendarPlaylistCoordinator, FilePlaylistStore, URL) {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let playlists = FilePlaylistStore(url: directory.appending(path: "playlists.json"))
    return (CalendarPlaylistCoordinator(url: directory.appending(path: "calendar.json"), playlists: playlists, library: CalendarLibraryStub(tracks)), playlists, directory)
}

private func classifiedTrack(_ title: String, language: String, category: ContentCategory? = nil, confidence: Double = 0) -> TrackSummary {
    TrackSummary(id: UUID(), title: title, artist: "Server Artist", language: language, contentClassifications: category.map { [.init(category: $0, confidence: confidence)] })
}

@Test("Calendar boundaries, manual correction, override, and preference precedence are explicit")
func calendarPreferenceBoundaries() async throws {
    let (coordinator, playlists, directory) = calendarFixture(); defer { try? FileManager.default.removeItem(at: directory) }
    let playlist = try await playlists.createPlaylist(name: "Chosen Quran")
    let start = Date(timeIntervalSince1970: 2_000_000_000), end = start.addingTimeInterval(86_400)
    try await coordinator.setCalendarWindow(.init(start: start, end: end, timeZoneIdentifier: "Asia/Dubai", version: "2027-manual", manuallyCorrected: true))
    try await coordinator.setPreference(.prefer, selectedPlaylistID: playlist.id)
    #expect(await coordinator.preferredPlaylist(at: start)?.id == playlist.id)
    #expect(await coordinator.preferredPlaylist(at: end) == nil)
    try await coordinator.setInstantOverride(true)
    #expect(await coordinator.preferredPlaylist(at: end)?.id == playlist.id)
    try await coordinator.setPreference(.off, selectedPlaylistID: playlist.id)
    #expect(await coordinator.preferredPlaylist(at: start) == nil)
    #expect((await coordinator.snapshot()).window?.manuallyCorrected == true)
}

@Test("Suggest never forces playback and deleted selections fail safely")
func calendarSuggestAndMissingPlaylist() async throws {
    let (coordinator, playlists, directory) = calendarFixture(); defer { try? FileManager.default.removeItem(at: directory) }
    let playlist = try await playlists.createPlaylist(name: "Suggestion")
    try await coordinator.setCalendarWindow(.init(start: .distantPast, end: .distantFuture, timeZoneIdentifier: "UTC", version: "fixture"))
    try await coordinator.setPreference(.suggest, selectedPlaylistID: playlist.id)
    #expect(await coordinator.suggestedPlaylist(at: Date())?.id == playlist.id)
    #expect(await coordinator.preferredPlaylist(at: Date()) == nil)
    try await playlists.deletePlaylist(id: playlist.id, expectedRevision: playlist.revision)
    #expect(await coordinator.suggestedPlaylist(at: Date()) == nil)
    await #expect(throws: CalendarPlaylistError.playlistMissing) { try await coordinator.setPreference(.prefer, selectedPlaylistID: playlist.id) }
}

@Test("Auto-grow off and unknown or low-confidence metadata make no changes")
func smartPlaylistSafeDefaults() async throws {
    let tracks = [
        classifiedTrack("Urdu unclassified", language: "ur"),
        classifiedTrack("Arabic low confidence", language: "ar", category: .quran, confidence: 0.79),
        classifiedTrack("English explicit", language: "en", category: .quranTranslation, confidence: 0.95),
    ]
    let (coordinator, playlists, directory) = calendarFixture(tracks); defer { try? FileManager.default.removeItem(at: directory) }
    let playlist = try await playlists.createPlaylist(name: "Smart")
    try await coordinator.setRule(.init(playlistID: playlist.id, automaticallyGrows: false, categories: [.quran, .quranTranslation], minimumConfidence: 0.8, weeklyAdditionLimit: 5, requiresApproval: false))
    try await coordinator.evaluateSmartPlaylists(at: Date(), calendar: .init(identifier: .gregorian))
    #expect(try await playlists.playlist(id: playlist.id).tracks.isEmpty)
    #expect((await coordinator.snapshot()).audit.isEmpty)
}

@Test("Approval is idempotent, weekly capped, auditable, and undoable across languages")
func smartPlaylistApprovalCapAndUndo() async throws {
    let tracks = [
        classifiedTrack("Urdu translation", language: "ur", category: .quranTranslation, confidence: 0.91),
        classifiedTrack("Arabic recitation", language: "ar", category: .quran, confidence: 0.99),
        classifiedTrack("English religious", language: "en", category: .religious, confidence: 0.99),
    ]
    let (coordinator, playlists, directory) = calendarFixture(tracks); defer { try? FileManager.default.removeItem(at: directory) }
    let playlist = try await playlists.createPlaylist(name: "Approval")
    try await coordinator.setRule(.init(playlistID: playlist.id, automaticallyGrows: true, categories: [.quran, .quranTranslation], minimumConfidence: 0.8, weeklyAdditionLimit: 2, requiresApproval: true))
    let date = Date(timeIntervalSince1970: 2_000_000_000); var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Dubai")!
    try await coordinator.evaluateSmartPlaylists(at: date, calendar: calendar)
    try await coordinator.evaluateSmartPlaylists(at: date, calendar: calendar)
    let proposal = try #require((await coordinator.snapshot()).pending.first)
    #expect(proposal.trackIDs.count == 2)
    #expect((await coordinator.snapshot()).pending.count == 1)
    try await coordinator.approve(auditID: proposal.id, at: date)
    let addition = try #require((await coordinator.snapshot()).audit.last(where: { $0.action == .added }))
    #expect(try await playlists.playlist(id: playlist.id).tracks.count == 2)
    try await coordinator.evaluateSmartPlaylists(at: date, calendar: calendar)
    #expect((await coordinator.snapshot()).pending.isEmpty)
    try await coordinator.undo(auditID: addition.id, at: date.addingTimeInterval(1))
    #expect(try await playlists.playlist(id: playlist.id).tracks.isEmpty)
    #expect((await coordinator.snapshot()).audit.last?.action == .undone)
}
