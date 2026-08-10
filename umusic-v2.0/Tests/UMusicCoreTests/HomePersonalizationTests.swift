import Foundation
import Testing
import UMusicCore
import UMusicDomain

private func homeTrack(_ value: String, year: Int? = nil) -> TrackSummary {
    TrackSummary(id: UUID(uuidString: value)!, title: value, artist: "Artist", releaseYear: year)
}

@Test("History uses calendar days across daylight-saving changes and excludes old entries")
func historyCalendarGroupingAcrossDST() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let parser = ISO8601DateFormatter()
    let track = homeTrack("00000000-0000-0000-0000-000000000001")
    let entries = [
        ListeningHistoryEntry(listenedAt: try #require(parser.date(from: "2026-03-08T06:30:00Z")), activity: .focus, track: track),
        ListeningHistoryEntry(listenedAt: try #require(parser.date(from: "2026-03-08T07:30:00Z")), activity: .walking, track: track),
        ListeningHistoryEntry(listenedAt: try #require(parser.date(from: "2026-03-07T18:00:00Z")), activity: .gym, track: track),
        ListeningHistoryEntry(listenedAt: try #require(parser.date(from: "2026-02-20T18:00:00Z")), activity: .unknown, track: track),
    ]
    let now = try #require(parser.date(from: "2026-03-09T12:00:00Z"))
    let groups = ListeningHistoryGrouper.group(entries, lastCalendarDays: 10, now: now, calendar: calendar)

    #expect(groups.count == 2)
    #expect(groups.map(\.entries.count) == [2, 1])
    #expect(groups.flatMap(\.entries).allSatisfy { $0.listenedAt >= calendar.date(byAdding: .day, value: -9, to: calendar.startOfDay(for: now))! })
}

@Test("History supports empty and sparse windows")
func historyEmptyAndSparse() {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(ListeningHistoryGrouper.group([], now: now, calendar: calendar).isEmpty)
    #expect(ListeningHistoryGrouper.group([], lastCalendarDays: 0, now: now, calendar: calendar).isEmpty)
}

@Test("Sprint 8 recommendation boundary is deterministic and cold-start safe")
func deterministicHomeRecommendation() async {
    let manager = PlaceholderPersonalizationManager()
    let tracks = [
        homeTrack("00000000-0000-0000-0000-000000000003"),
        homeTrack("00000000-0000-0000-0000-000000000001"),
        homeTrack("00000000-0000-0000-0000-000000000002"),
    ]
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(await manager.recommendedQueue(from: [], at: date, limit: 25).isEmpty)
    let first = await manager.recommendedQueue(from: tracks, at: date, limit: 2)
    let second = await manager.recommendedQueue(from: tracks.reversed(), at: date, limit: 2)
    #expect(first == second)
    #expect(first.count == 2)
    #expect(await manager.recentHistory(lastCalendarDays: 10, now: date, calendar: .current).isEmpty)
}

