import Foundation

public enum ListeningActivity: String, Codable, CaseIterable, Sendable {
    case unknown
    case walking
    case running
    case cycling
    case gym
    case focus
    case relaxation

    public var displayName: String {
        switch self {
        case .unknown: "Listening"
        case .walking: "Walking"
        case .running: "Running"
        case .cycling: "Cycling"
        case .gym: "Gym"
        case .focus: "Focus"
        case .relaxation: "Relaxation"
        }
    }
}

/// A privacy-safe Home summary. Precise coordinates and place names are intentionally absent.
public struct ListeningHistoryEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let listenedAt: Date
    public let activity: ListeningActivity
    public let track: TrackSummary

    public init(id: UUID = UUID(), listenedAt: Date, activity: ListeningActivity, track: TrackSummary) {
        self.id = id
        self.listenedAt = listenedAt
        self.activity = activity
        self.track = track
    }
}

public struct ListeningHistoryDay: Equatable, Sendable, Identifiable {
    public var id: Date { day }
    public let day: Date
    public let entries: [ListeningHistoryEntry]

    public init(day: Date, entries: [ListeningHistoryEntry]) {
        self.day = day
        self.entries = entries
    }
}

public enum ListeningHistoryGrouper {
    /// Groups the inclusive calendar-day window containing `now`, using the supplied calendar/time zone.
    public static func group(
        _ entries: [ListeningHistoryEntry],
        lastCalendarDays limit: Int = 10,
        now: Date,
        calendar: Calendar
    ) -> [ListeningHistoryDay] {
        guard limit > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        guard let earliest = calendar.date(byAdding: .day, value: -(limit - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }

        let relevant = entries.filter { $0.listenedAt >= earliest && $0.listenedAt < end }
        let grouped = Dictionary(grouping: relevant) { calendar.startOfDay(for: $0.listenedAt) }
        return grouped.keys.sorted(by: >).map { day in
            ListeningHistoryDay(
                day: day,
                entries: grouped[day, default: []].sorted { $0.listenedAt > $1.listenedAt }
            )
        }
    }
}

