import Foundation
import UMusicDomain
import UMusicSupport
import UMusicML

public enum LearningModule {
    public static let runsLocally = true
    public static let schemaVersion = 1
    public static let lowEnergyBatchSeconds = 120
    public static let batchEventCount = 25
}

public enum LearningStoreError: Error, Equatable { case unsupportedSchema, corruptStore }

private struct LearningDocument: Codable, Sendable {
    var schemaVersion = LearningModule.schemaVersion
    var nextSequence: Int64 = 1
    var retention = RawHistoryRetention.ninetyDays
    var events: [EventEnvelope] = []
    var sessions: [PlaybackSession] = []
    var observations: [PlaybackObservation] = []
    var contexts: [ContextSnapshot] = []
    var aggregates: [UUID: TrackAffinityAggregate] = [:]
    var featureAggregates: [String: FeatureAggregate] = [:]
    var reducedObservationIDs: Set<UUID> = []
    var trackSnapshots: [UUID: TrackSummary] = [:]
    var consents: [ConsentRecord] = []
    var lastReducedSequence: Int64 = 0
}

private struct SanitizedLearningExport: Codable {
    let schemaVersion: Int
    let redactionLevel: String
    let generatedAt: Date
    let events: [EventEnvelope]
    let observations: [PlaybackObservation]
    let contexts: [ContextSnapshot]
    let aggregates: [TrackAffinityAggregate]
    let featureAggregates: [FeatureAggregate]
    let consents: [ConsentRecord]
}

public actor LocalLearningStore: PersonalizationManaging, PlaybackLearningRecording, ContextLearningRecording {
    private let url: URL
    private var document: LearningDocument
    private var pendingEvents: [EventEnvelope] = []
    private var sessionID = UUID()
    private var sessionStartedAt = Date()
    private var context: ContextSnapshot
    private var currentObservation: PlaybackObservation?
    private var currentPositionMilliseconds: Int64 = 0
    private var lastCheckpointMilliseconds: Int64 = 0
    private var flushTask: Task<Void, Never>?
    private var persistenceBlocked: Bool
    private var fullExportPreview: ResearchExportPreview?
    private let modelRanker: ModelRankerLifecycle?

    public init(url: URL, modelRanker: ModelRankerLifecycle? = nil) {
        self.url = url
        self.modelRanker = modelRanker
        let result = Self.load(from: url)
        document = result.document
        persistenceBlocked = result.blocked
        let now = Date()
        context = ContextSnapshot(date: now, calendar: .autoupdatingCurrent)
        sessionStartedAt = now
        if !result.blocked {
            document.sessions.append(PlaybackSession(id: sessionID, startedAt: now))
            pendingEvents.append(EventEnvelope(sequence: document.nextSequence, sessionID: sessionID, type: .sessionStarted, occurredAt: now, monotonicMilliseconds: 0))
            document.nextSequence += 1
        }
        if !FileManager.default.fileExists(atPath: url.path), !result.blocked { try? Self.persist(document, to: url) }
    }

    deinit { flushTask?.cancel() }

    public func recommendedQueue(from tracks: [TrackSummary], at date: Date, limit: Int) async -> [TrackSummary] {
        let result = await recommendations(from: tracks, at: date, offlineTrackIDs: [], excluding: [], limit: limit)
        return result.items.map(\.track)
    }

    public func recommendations(from tracks: [TrackSummary], at date: Date, offlineTrackIDs: Set<UUID>, excluding trackIDs: Set<UUID>, limit: Int) async -> RecommendationResult {
        let eligible = tracks.filter { !trackIDs.contains($0.id) }
        let profile = RecommendationProfile(trackAffinities: document.aggregates, featureAggregates: document.featureAggregates, activity: context.activity, localHour: context.localHour)
        let seed = UInt64(max(date.timeIntervalSince1970 / 3_600, 0))
        let modelRanker = self.modelRanker
        return await withTaskGroup(of: RecommendationResult?.self) { group in
            group.addTask {
                let candidateLimit = min(max(limit * 8, 200), eligible.count)
                let heuristic = HeuristicRecommendationEngine.rank(tracks: eligible, profile: profile, offlineTrackIDs: offlineTrackIDs, excluding: [], limit: candidateLimit, now: date, seed: seed)
                guard let modelRanker else { return Self.limited(heuristic, to: limit) }
                let features = heuristic.items.map { Self.modelFeatures(candidate: $0, profile: profile, offlineTrackIDs: offlineTrackIDs) }
                switch await modelRanker.rank(features) {
                case .scored(let scores, let mode, let modelVersion, let featureVersion):
                    if mode == .shadow {
                        return RecommendationResult(engineVersion: heuristic.engineVersion, generatedAt: date, items: Array(heuristic.items.prefix(limit)), trace: .init(mode: .shadow, modelVersion: modelVersion, featureVersion: featureVersion))
                    }
                    var scored: [RecommendedTrack] = []
                    scored.reserveCapacity(scores.count)
                    for (item, score) in zip(heuristic.items, scores) {
                        var reasons = Set(item.reasons); reasons.insert(.modelRanker)
                        scored.append(RecommendedTrack(track: item.track, score: score, reasons: reasons.sorted { $0.rawValue < $1.rawValue }))
                    }
                    scored.sort { lhs, rhs in lhs.score == rhs.score ? lhs.id.uuidString < rhs.id.uuidString : lhs.score > rhs.score }
                    return RecommendationResult(engineVersion: "coreml-\(modelVersion)", generatedAt: date, items: HeuristicRecommendationEngine.policyRerank(scored, limit: limit), trace: .init(mode: .model, modelVersion: modelVersion, featureVersion: featureVersion))
                case .fallback(let code):
                    let items = heuristic.items.prefix(limit).map { RecommendedTrack(track: $0.track, score: $0.score, reasons: Array(Set($0.reasons + [.modelFallback])).sorted { $0.rawValue < $1.rawValue }) }
                    return RecommendationResult(engineVersion: heuristic.engineVersion, generatedAt: date, items: Array(items), trace: .init(mode: .fallback, featureVersion: "ranker-features-1", fallbackCode: code))
                }
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return nil }
                return HeuristicRecommendationEngine.fallback(tracks: eligible, limit: limit, now: date, seed: seed, timedOut: true)
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result ?? HeuristicRecommendationEngine.fallback(tracks: eligible, limit: limit, now: date, seed: seed, timedOut: true)
        }
    }

    private static func limited(_ result: RecommendationResult, to limit: Int) -> RecommendationResult {
        RecommendationResult(engineVersion: result.engineVersion, generatedAt: result.generatedAt, items: Array(result.items.prefix(limit)), usedFallback: result.usedFallback, trace: result.trace)
    }

    private static func modelFeatures(candidate: RecommendedTrack, profile: RecommendationProfile, offlineTrackIDs: Set<UUID>) -> [Double] {
        let affinity = profile.trackAffinities[candidate.id]
        let exposures = Double(affinity?.exposures ?? 0), completionRate = exposures > 0 ? Double(affinity?.completions ?? 0) / exposures : 0, skipRate = exposures > 0 ? Double(affinity?.skips ?? 0) / exposures : 0
        let angle = Double(profile.localHour) / 24 * 2 * Double.pi
        return [candidate.score, completionRate, skipRate, log1p(exposures), offlineTrackIDs.contains(candidate.id) ? 1 : 0, sin(angle), cos(angle), Double((candidate.track.releaseYear ?? 2000) - 1900) / 200]
    }

    public func recentHistory(lastCalendarDays: Int, now: Date, calendar: Calendar) async -> [ListeningHistoryDay] {
        let entries = document.observations.compactMap { observation -> ListeningHistoryEntry? in
            guard let track = document.trackSnapshots[observation.trackID] else { return nil }
            let observationContext = document.contexts.first(where: { $0.id == observation.contextID })
            let activity = observationContext?.activity ?? .unknown
            return ListeningHistoryEntry(id: observation.id, listenedAt: observation.startedAt, activity: activity, track: track)
        }
        return ListeningHistoryGrouper.group(entries, lastCalendarDays: lastCalendarDays, now: now, calendar: calendar)
    }

    public func learningSnapshot() async -> LearningSnapshot {
        LearningSnapshot(retention: document.retention, eventCount: document.events.count + pendingEvents.count, observationCount: document.observations.count + (currentObservation == nil ? 0 : 1), aggregateCount: document.aggregates.count + document.featureAggregates.count, lastReducedSequence: document.lastReducedSequence)
    }

    public func setRawHistoryRetention(_ retention: RawHistoryRetention) async throws {
        document.retention = retention
        try compact(now: Date())
    }

    public func deleteHistory() async throws {
        pendingEvents.removeAll(); currentObservation = nil
        document.events.removeAll(); document.observations.removeAll(); document.contexts.removeAll()
        document.sessions.removeAll()
        document.trackSnapshots.removeAll(); document.reducedObservationIDs.removeAll()
        document.lastReducedSequence = 0
        try persistNow()
    }

    public func resetLearning() async throws {
        try await deleteHistory()
        document.aggregates.removeAll()
        document.featureAggregates.removeAll()
        try persistNow()
    }

    public func exportSanitized() async throws -> URL {
        try flushPending()
        let export = SanitizedLearningExport(schemaVersion: document.schemaVersion, redactionLevel: "sanitized", generatedAt: Date(), events: document.events, observations: document.observations, contexts: document.contexts, aggregates: document.aggregates.values.sorted { $0.trackID.uuidString < $1.trackID.uuidString }, featureAggregates: document.featureAggregates.values.sorted { $0.featureKey < $1.featureKey }, consents: document.consents)
        let exportURL = FileManager.default.temporaryDirectory.appending(path: "umusic-sanitized-learning-\(Int(Date().timeIntervalSince1970)).json")
        let data = try JSONEncoder.exportEncoder.encode(export)
        try data.write(to: exportURL, options: [.atomic, .completeFileProtection])
        return exportURL
    }

    public func previewFullResearchExport() async -> ResearchExportPreview {
        let preview = ResearchExportPreview(eventCount: document.events.count + pendingEvents.count, observationCount: document.observations.count + (currentObservation == nil ? 0 : 1), includesTrackMetadata: true, sensitiveCategories: ["track titles and artists", "complete listening timeline", "coarse activity and context"], expiresAt: Date().addingTimeInterval(300))
        fullExportPreview = preview; return preview
    }

    public func exportResearch(_ kind: ResearchExportKind, confirmationID: UUID?) async throws -> URL {
        if kind == .full {
            guard let preview = fullExportPreview, preview.confirmationID == confirmationID else { throw ResearchExportError.confirmationRequired }
            guard preview.expiresAt > Date() else { fullExportPreview = nil; throw ResearchExportError.confirmationExpired }
            fullExportPreview = nil
        }
        try flushPending()
        ResearchPackageWriter.cleanup()
        return try await ResearchPackageWriter.write(records: exportRecords(), kind: kind)
    }

    public func cleanupResearchExports() async { ResearchPackageWriter.cleanup(olderThan: Date().addingTimeInterval(1)) }

    private func exportRecords() -> ResearchExportRecords {
        ResearchExportRecords(events: document.events, sessions: document.sessions, observations: document.observations, contexts: document.contexts, aggregates: document.aggregates.values.sorted { $0.trackID.uuidString < $1.trackID.uuidString }, featureAggregates: document.featureAggregates.values.sorted { $0.featureKey < $1.featureKey }, consents: document.consents, tracks: document.trackSnapshots.values.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    public func record(_ transition: PlaybackLearningTransition) async {
        let now = Date()
        switch transition {
        case .started(let track, let position):
            finishCurrent(at: now, reason: .replaced)
            if document.contexts.allSatisfy({ $0.id != context.id }) { document.contexts.append(context) }
            document.trackSnapshots[track.id] = track
            currentPositionMilliseconds = milliseconds(position)
            lastCheckpointMilliseconds = currentPositionMilliseconds
            currentObservation = PlaybackObservation(sessionID: sessionID, trackID: track.id, contextID: context.id, startedAt: now, durationMilliseconds: track.durationSeconds.map(milliseconds))
            append(.trackStarted, now: now, trackID: track.id, position: currentPositionMilliseconds)
        case .resumed(let position):
            currentPositionMilliseconds = milliseconds(position); append(.trackResumed, now: now, trackID: currentObservation?.trackID, position: currentPositionMilliseconds)
        case .paused(let position):
            checkpoint(position: position, duration: nil); append(.trackPaused, now: now, trackID: currentObservation?.trackID, position: milliseconds(position)); try? flushPending()
        case .seeked(let from, let to):
            checkpoint(position: from, duration: nil); currentPositionMilliseconds = milliseconds(to)
            if var observation = currentObservation { observation.seekCount += 1; currentObservation = observation }
            append(.trackSeeked, now: now, trackID: currentObservation?.trackID, position: currentPositionMilliseconds)
        case .ended(let position, let duration, let reason):
            let trackID = currentObservation?.trackID
            checkpoint(position: position, duration: duration); finishCurrent(at: now, reason: reason)
            append(reason == .skipped ? .trackSkipped : .trackEnded, now: now, trackID: trackID, position: milliseconds(position), duration: duration.map(milliseconds), reason: reason)
            try? flushPending()
        case .checkpoint(let position, let duration):
            checkpoint(position: position, duration: duration)
            if abs(currentPositionMilliseconds - lastCheckpointMilliseconds) >= 15_000 {
                lastCheckpointMilliseconds = currentPositionMilliseconds
                try? persistNow() // updates the observation checkpoint; it does not create an event.
            }
        case .technicalFailure(let position):
            let trackID = currentObservation?.trackID
            checkpoint(position: position, duration: nil); finishCurrent(at: now, reason: .technicalFailure)
            append(.technicalFailure, now: now, trackID: trackID, position: milliseconds(position), reason: .technicalFailure)
            try? flushPending()
        }
    }

    public func flush() async { try? flushPending() }

    public func recordConsent(signal: String, status: ConsentStatus, policyVersion: Int = 1) throws {
        document.consents.append(ConsentRecord(signal: signal, status: status, policyVersion: policyVersion, recordedAt: Date()))
        try persistNow()
    }

    public func recordContextConsent(signal: ContextSignal, status: ConsentStatus) async {
        try? recordConsent(signal: "context:\(signal.rawValue)", status: status)
    }

    public func updateContext(_ snapshot: ContextSnapshot) async {
        guard snapshot != context else { return }
        context = snapshot
        if document.contexts.allSatisfy({ $0.id != snapshot.id }) { document.contexts.append(snapshot) }
        append(.contextChanged, now: snapshot.capturedAt)
    }

    func ingestEventEnvelopes(_ events: [EventEnvelope]) throws {
        var known = Set(document.events.map(\.id)).union(pendingEvents.map(\.id))
        var unique: [EventEnvelope] = []
        for event in events.sorted(by: { $0.sequence < $1.sequence }) where known.insert(event.id).inserted { unique.append(event) }
        pendingEvents.append(contentsOf: unique)
        document.nextSequence = max(document.nextSequence, (events.map(\.sequence).max() ?? 0) + 1)
        try flushPending()
    }

    public func compact(now: Date) throws {
        reduceCompletedObservations()
        if let days = document.retention.dayCount {
            let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: now) ?? .distantPast
            let expiredIDs = Set(document.observations.lazy.filter { $0.startedAt < cutoff }.map(\.id))
            document.observations.removeAll { expiredIDs.contains($0.id) }
            document.events.removeAll { $0.occurredAt < cutoff }
            document.reducedObservationIDs.subtract(expiredIDs)
            let usedContexts = Set(document.observations.map(\.contextID))
            document.contexts.removeAll { !usedContexts.contains($0.id) }
        }
        try persistNow()
    }

    private func finishCurrent(at date: Date, reason: PlaybackEndReason) {
        guard var observation = currentObservation else { return }
        observation.endedAt = date; observation.endReason = reason
        document.observations.append(observation); currentObservation = nil
    }

    private func checkpoint(position: Double, duration: Double?) {
        let newPosition = milliseconds(position)
        guard var observation = currentObservation else { currentPositionMilliseconds = newPosition; return }
        if newPosition >= currentPositionMilliseconds { observation.listenedMilliseconds += newPosition - currentPositionMilliseconds }
        if let duration { observation.durationMilliseconds = milliseconds(duration) }
        currentPositionMilliseconds = newPosition; currentObservation = observation
    }

    private func append(_ type: LearningEventType, now: Date, trackID: UUID? = nil, position: Int64? = nil, duration: Int64? = nil, reason: PlaybackEndReason? = nil) {
        if [.trackPaused, .trackResumed, .trackSeeked].contains(type), let previous = pendingEvents.last,
           previous.type == type, previous.trackID == (trackID ?? currentObservation?.trackID), now.timeIntervalSince(previous.occurredAt) < 2 {
            pendingEvents[pendingEvents.count - 1] = EventEnvelope(id: previous.id, sequence: previous.sequence, sessionID: sessionID, type: type, occurredAt: now, monotonicMilliseconds: milliseconds(now.timeIntervalSince(sessionStartedAt)), trackID: trackID ?? currentObservation?.trackID, positionMilliseconds: position, durationMilliseconds: duration, endReason: reason)
            return
        }
        let event = EventEnvelope(sequence: document.nextSequence, sessionID: sessionID, type: type, occurredAt: now, monotonicMilliseconds: milliseconds(now.timeIntervalSince(sessionStartedAt)), trackID: trackID ?? currentObservation?.trackID, positionMilliseconds: position, durationMilliseconds: duration, endReason: reason)
        document.nextSequence += 1; pendingEvents.append(event)
        if pendingEvents.count >= LearningModule.batchEventCount { try? flushPending() } else { scheduleFlush() }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task {
            try? await Task.sleep(for: .seconds(LearningModule.lowEnergyBatchSeconds))
            guard !Task.isCancelled else { return }
            self.flushTask = nil
            try? self.flushPending()
        }
    }

    private func flushPending() throws {
        flushTask?.cancel(); flushTask = nil
        let existing = Set(document.events.map(\.id))
        document.events.append(contentsOf: pendingEvents.filter { !existing.contains($0.id) })
        pendingEvents.removeAll(); reduceCompletedObservations(); try persistNow()
    }

    private func reduceCompletedObservations() {
        for observation in document.observations where !document.reducedObservationIDs.contains(observation.id) {
            var aggregate = document.aggregates[observation.trackID] ?? TrackAffinityAggregate(trackID: observation.trackID, exposures: 0, completions: 0, skips: 0, listenedMilliseconds: 0, lastUpdatedAt: observation.startedAt)
            aggregate.exposures += observation.exposureCount
            aggregate.completions += observation.endReason == .completed ? 1 : 0
            aggregate.skips += observation.endReason == .skipped ? 1 : 0
            aggregate.listenedMilliseconds += observation.listenedMilliseconds
            aggregate.lastUpdatedAt = observation.endedAt ?? observation.startedAt
            document.aggregates[observation.trackID] = aggregate
            let observationContext = document.contexts.first(where: { $0.id == observation.contextID })
            let activity = observationContext?.activity ?? .unknown
            let key = "activity:\(activity.rawValue)"
            var feature = document.featureAggregates[key] ?? FeatureAggregate(featureKey: key, lastUpdatedAt: observation.startedAt)
            feature.exposures += observation.exposureCount
            feature.completions += observation.endReason == .completed ? 1 : 0
            feature.listenedMilliseconds += observation.listenedMilliseconds
            feature.lastUpdatedAt = observation.endedAt ?? observation.startedAt
            document.featureAggregates[key] = feature
            if let track = document.trackSnapshots[observation.trackID] {
                let time = HeuristicRecommendationEngine.timeBucket(observationContext?.localHour ?? 12)
                updateFeature("activity:\(activity.rawValue)|time:\(time)|track:\(track.id.uuidString.lowercased())", observation: observation)
                updateFeature("activity:\(activity.rawValue)|track:\(track.id.uuidString.lowercased())", observation: observation)
                updateFeature("time:\(time)|track:\(track.id.uuidString.lowercased())", observation: observation)
                updateFeature("artist:\(track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())", observation: observation)
                if let album = track.album { updateFeature("album:\(album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())", observation: observation) }
                for genre in track.genres ?? [] { updateFeature("genre:\(genre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())", observation: observation) }
                if let language = track.language { updateFeature("language:\(language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())", observation: observation) }
                if let year = track.releaseYear { updateFeature("era:\((year / 10) * 10)", observation: observation) }
            }
            document.reducedObservationIDs.insert(observation.id)
        }
        document.lastReducedSequence = max(document.lastReducedSequence, document.events.last?.sequence ?? 0)
    }

    private func updateFeature(_ key: String, observation: PlaybackObservation) {
        var feature = document.featureAggregates[key] ?? FeatureAggregate(featureKey: key, lastUpdatedAt: observation.startedAt)
        feature.exposures += observation.exposureCount
        feature.completions += observation.endReason == .completed ? 1 : 0
        feature.listenedMilliseconds += observation.listenedMilliseconds
        feature.lastUpdatedAt = observation.endedAt ?? observation.startedAt
        document.featureAggregates[key] = feature
    }

    private func persistNow() throws {
        guard !persistenceBlocked else { throw LearningStoreError.unsupportedSchema }
        try Self.persist(document, currentObservation: currentObservation, to: url)
    }
    private func milliseconds(_ seconds: Double) -> Int64 { Int64(max(seconds, 0) * 1_000) }

    private static func load(from url: URL) -> (document: LearningDocument, blocked: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (LearningDocument(), false) }
        guard let data = try? Data(contentsOf: url), var value = try? JSONDecoder().decode(LearningDocument.self, from: data) else { return (LearningDocument(), true) }
        if value.schemaVersion == 0 { value.schemaVersion = LearningModule.schemaVersion; return (value, false) }
        guard value.schemaVersion == LearningModule.schemaVersion else { return (LearningDocument(), true) }
        return (value, false)
    }

    private static func persist(_ document: LearningDocument, currentObservation: PlaybackObservation? = nil, to url: URL) throws {
        var value = document
        if let currentObservation, !value.observations.contains(where: { $0.id == currentObservation.id }) { value.observations.append(currentObservation) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.storeEncoder.encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}

private extension JSONEncoder {
    static var storeEncoder: JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .millisecondsSince1970; value.outputFormatting = [.sortedKeys]; return value }
    static var exportEncoder: JSONEncoder { let value = storeEncoder; value.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return value }
}
