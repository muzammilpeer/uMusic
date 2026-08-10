import Foundation

public enum ContentCategory: String, Codable, CaseIterable, Sendable {
    case quran
    case quranTranslation
    case religious
}

public struct ContentClassification: Codable, Equatable, Hashable, Sendable {
    public let category: ContentCategory
    public let confidence: Double
    public init(category: ContentCategory, confidence: Double) {
        self.category = category
        self.confidence = min(max(confidence, 0), 1)
    }
}

public enum RamadanPreference: String, Codable, CaseIterable, Sendable {
    case off
    case suggest
    case prefer
}

public struct CalendarWindow: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let timeZoneIdentifier: String
    public let version: String
    public let manuallyCorrected: Bool
    public init(start: Date, end: Date, timeZoneIdentifier: String, version: String, manuallyCorrected: Bool = false) {
        self.start = start; self.end = end; self.timeZoneIdentifier = timeZoneIdentifier
        self.version = version; self.manuallyCorrected = manuallyCorrected
    }
    public func contains(_ date: Date) -> Bool { start <= date && date < end }
}

public struct SmartPlaylistRule: Codable, Equatable, Sendable {
    public let playlistID: UUID
    public let automaticallyGrows: Bool
    public let categories: Set<ContentCategory>
    public let minimumConfidence: Double
    public let weeklyAdditionLimit: Int
    public let requiresApproval: Bool
    public init(playlistID: UUID, automaticallyGrows: Bool = false, categories: Set<ContentCategory> = [], minimumConfidence: Double = 0.8, weeklyAdditionLimit: Int = 10, requiresApproval: Bool = true) {
        self.playlistID = playlistID; self.automaticallyGrows = automaticallyGrows
        self.categories = categories; self.minimumConfidence = min(max(minimumConfidence, 0), 1)
        self.weeklyAdditionLimit = min(max(weeklyAdditionLimit, 0), 100); self.requiresApproval = requiresApproval
    }
}

public enum SmartPlaylistAuditAction: String, Codable, Sendable { case proposed, added, undone }

public struct SmartPlaylistAuditEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let playlistID: UUID
    public let trackIDs: [UUID]
    public let action: SmartPlaylistAuditAction
    public let reason: String
    public let occurredAt: Date
    public init(id: UUID = UUID(), playlistID: UUID, trackIDs: [UUID], action: SmartPlaylistAuditAction, reason: String, occurredAt: Date) {
        self.id = id; self.playlistID = playlistID; self.trackIDs = trackIDs
        self.action = action; self.reason = reason; self.occurredAt = occurredAt
    }
}

public struct CalendarPreferenceSnapshot: Codable, Equatable, Sendable {
    public let preference: RamadanPreference
    public let selectedPlaylistID: UUID?
    public let window: CalendarWindow?
    public let instantOverride: Bool?
    public let rules: [SmartPlaylistRule]
    public let pending: [SmartPlaylistAuditEntry]
    public let audit: [SmartPlaylistAuditEntry]
    public init(preference: RamadanPreference = .off, selectedPlaylistID: UUID? = nil, window: CalendarWindow? = nil, instantOverride: Bool? = nil, rules: [SmartPlaylistRule] = [], pending: [SmartPlaylistAuditEntry] = [], audit: [SmartPlaylistAuditEntry] = []) {
        self.preference = preference; self.selectedPlaylistID = selectedPlaylistID; self.window = window
        self.instantOverride = instantOverride; self.rules = rules; self.pending = pending; self.audit = audit
    }
}

public enum CalendarPlaylistError: Error, Equatable { case playlistMissing, conflict, auditEntryMissing }

public protocol CalendarPreferenceManaging: Sendable {
    func snapshot() async -> CalendarPreferenceSnapshot
    func setPreference(_ preference: RamadanPreference, selectedPlaylistID: UUID?) async throws
    func setCalendarWindow(_ window: CalendarWindow?) async throws
    func setInstantOverride(_ active: Bool?) async throws
    func setRule(_ rule: SmartPlaylistRule) async throws
    func preferredPlaylist(at date: Date) async -> ManualPlaylist?
    func suggestedPlaylist(at date: Date) async -> ManualPlaylist?
    func evaluateSmartPlaylists(at date: Date, calendar: Calendar) async throws
    func approve(auditID: UUID, at date: Date) async throws
    func undo(auditID: UUID, at date: Date) async throws
}
