import Foundation
import UMusicDomain

private struct CalendarPreferenceDocument: Codable {
    var snapshot = CalendarPreferenceSnapshot()
}

public actor CalendarPlaylistCoordinator: CalendarPreferenceManaging {
    private let url: URL
    private let playlists: any PlaylistManaging
    private let library: any LibraryProviding
    private var document: CalendarPreferenceDocument

    public init(url: URL, playlists: any PlaylistManaging, library: any LibraryProviding) {
        self.url = url; self.playlists = playlists; self.library = library
        document = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(CalendarPreferenceDocument.self, from: $0) } ?? CalendarPreferenceDocument()
    }

    public func snapshot() async -> CalendarPreferenceSnapshot { document.snapshot }

    public func setPreference(_ preference: RamadanPreference, selectedPlaylistID: UUID?) async throws {
        if let selectedPlaylistID { guard (try? await playlists.playlist(id: selectedPlaylistID)) != nil else { throw CalendarPlaylistError.playlistMissing } }
        replace(preference: preference, selectedPlaylistID: selectedPlaylistID); try persist()
    }

    public func setCalendarWindow(_ window: CalendarWindow?) async throws {
        replace(window: window); try persist()
    }

    public func setInstantOverride(_ active: Bool?) async throws {
        replace(instantOverride: active); try persist()
    }

    public func setRule(_ rule: SmartPlaylistRule) async throws {
        guard let playlist = try? await playlists.playlist(id: rule.playlistID) else { throw CalendarPlaylistError.playlistMissing }
        do { _ = try await playlists.setAutomaticallyGrows(rule.automaticallyGrows, for: playlist.id, expectedRevision: playlist.revision) }
        catch PlaylistStoreError.conflict { throw CalendarPlaylistError.conflict }
        var rules = document.snapshot.rules.filter { $0.playlistID != rule.playlistID }; rules.append(rule)
        replace(rules: rules.sorted { $0.playlistID.uuidString < $1.playlistID.uuidString }); try persist()
    }

    public func preferredPlaylist(at date: Date) async -> ManualPlaylist? {
        guard document.snapshot.preference == .prefer, isActive(at: date), let id = document.snapshot.selectedPlaylistID else { return nil }
        return try? await playlists.playlist(id: id)
    }

    public func suggestedPlaylist(at date: Date) async -> ManualPlaylist? {
        guard document.snapshot.preference == .suggest, isActive(at: date), let id = document.snapshot.selectedPlaylistID else { return nil }
        return try? await playlists.playlist(id: id)
    }

    public func evaluateSmartPlaylists(at date: Date, calendar: Calendar) async throws {
        let tracks = try await library.browse(.init())
        for rule in document.snapshot.rules where rule.automaticallyGrows {
            guard var playlist = try? await playlists.playlist(id: rule.playlistID) else { continue }
            let existing = Set(playlist.tracks.map(\.id))
            let used = weeklyAddedCount(playlistID: rule.playlistID, date: date, calendar: calendar)
            let room = max(rule.weeklyAdditionLimit - used, 0)
            guard room > 0 else { continue }
            let matches = tracks.filter { track in
                !existing.contains(track.id) && (track.contentClassifications ?? []).contains { rule.categories.contains($0.category) && $0.confidence >= rule.minimumConfidence }
            }.sorted { $0.id.uuidString < $1.id.uuidString }
            let selected = Array(matches.prefix(room)); guard !selected.isEmpty else { continue }
            let reason = "Server content classification matched the playlist rule at or above the configured confidence."
            if rule.requiresApproval {
                let alreadyPending = Set(document.snapshot.pending.filter { $0.playlistID == rule.playlistID }.flatMap(\.trackIDs))
                let proposed = selected.filter { !alreadyPending.contains($0.id) }
                guard !proposed.isEmpty else { continue }
                let entry = SmartPlaylistAuditEntry(playlistID: rule.playlistID, trackIDs: proposed.map(\.id), action: .proposed, reason: reason, occurredAt: date)
                replace(pending: document.snapshot.pending + [entry], audit: document.snapshot.audit + [entry])
            } else {
                var added: [UUID] = []
                for track in selected {
                    do { playlist = try await playlists.addTrack(track, to: playlist.id, expectedRevision: playlist.revision); added.append(track.id) }
                    catch PlaylistStoreError.conflict { throw CalendarPlaylistError.conflict }
                }
                if !added.isEmpty {
                    let entry = SmartPlaylistAuditEntry(playlistID: rule.playlistID, trackIDs: added, action: .added, reason: reason, occurredAt: date)
                    replace(audit: document.snapshot.audit + [entry])
                }
            }
        }
        try persist()
    }

    public func approve(auditID: UUID, at date: Date) async throws {
        guard let proposal = document.snapshot.pending.first(where: { $0.id == auditID }) else { throw CalendarPlaylistError.auditEntryMissing }
        guard var playlist = try? await playlists.playlist(id: proposal.playlistID) else { throw CalendarPlaylistError.playlistMissing }
        let catalog = try await library.browse(.init()); let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        var added: [UUID] = []
        for id in proposal.trackIDs where !playlist.tracks.contains(where: { $0.id == id }) {
            guard let track = byID[id] else { continue }
            do { playlist = try await playlists.addTrack(track, to: playlist.id, expectedRevision: playlist.revision); added.append(id) }
            catch PlaylistStoreError.conflict { throw CalendarPlaylistError.conflict }
        }
        let entry = SmartPlaylistAuditEntry(playlistID: proposal.playlistID, trackIDs: added, action: .added, reason: proposal.reason, occurredAt: date)
        replace(pending: document.snapshot.pending.filter { $0.id != auditID }, audit: document.snapshot.audit + [entry]); try persist()
    }

    public func undo(auditID: UUID, at date: Date) async throws {
        guard let addition = document.snapshot.audit.first(where: { $0.id == auditID && $0.action == .added }) else { throw CalendarPlaylistError.auditEntryMissing }
        guard var playlist = try? await playlists.playlist(id: addition.playlistID) else { throw CalendarPlaylistError.playlistMissing }
        for id in addition.trackIDs.reversed() {
            guard let index = playlist.tracks.lastIndex(where: { $0.id == id }) else { continue }
            do { playlist = try await playlists.removeTrack(at: index, from: playlist.id, expectedRevision: playlist.revision) }
            catch PlaylistStoreError.conflict { throw CalendarPlaylistError.conflict }
        }
        let entry = SmartPlaylistAuditEntry(playlistID: addition.playlistID, trackIDs: addition.trackIDs, action: .undone, reason: "Undid automatic playlist additions.", occurredAt: date)
        replace(audit: document.snapshot.audit + [entry]); try persist()
    }

    private func isActive(at date: Date) -> Bool {
        if let override = document.snapshot.instantOverride { return override }
        return document.snapshot.window?.contains(date) ?? false
    }

    private func weeklyAddedCount(playlistID: UUID, date: Date, calendar: Calendar) -> Int {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return document.snapshot.audit.filter { $0.playlistID == playlistID && $0.action == .added && interval.contains($0.occurredAt) }.reduce(0) { $0 + $1.trackIDs.count }
    }

    private func replace(preference: RamadanPreference? = nil, selectedPlaylistID: UUID?? = nil, window: CalendarWindow?? = nil, instantOverride: Bool?? = nil, rules: [SmartPlaylistRule]? = nil, pending: [SmartPlaylistAuditEntry]? = nil, audit: [SmartPlaylistAuditEntry]? = nil) {
        let old = document.snapshot
        document.snapshot = CalendarPreferenceSnapshot(preference: preference ?? old.preference, selectedPlaylistID: selectedPlaylistID ?? old.selectedPlaylistID, window: window ?? old.window, instantOverride: instantOverride ?? old.instantOverride, rules: rules ?? old.rules, pending: pending ?? old.pending, audit: audit ?? old.audit)
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(document).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
