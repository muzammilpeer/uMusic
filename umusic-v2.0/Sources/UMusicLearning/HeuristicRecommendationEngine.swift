import Foundation
import UMusicDomain

public enum HeuristicRecommendationEngine {
    public static let version = "heuristic-1"

    public static func rank(tracks: [TrackSummary], profile: RecommendationProfile, offlineTrackIDs: Set<UUID>, excluding: Set<UUID>, limit: Int, now: Date, seed: UInt64) -> RecommendationResult {
        guard limit > 0 else { return RecommendationResult(engineVersion: version, generatedAt: now, items: []) }
        let eligible = tracks.filter { !excluding.contains($0.id) }
        let coldStart = profile.trackAffinities.isEmpty && profile.featureAggregates.isEmpty
        var candidates: [RecommendedTrack] = []
        candidates.reserveCapacity(eligible.count)
        for (index, track) in eligible.enumerated() {
            if index.isMultiple(of: 256), Task.isCancelled { return fallback(tracks: eligible, limit: limit, now: now, seed: seed, timedOut: true) }
            var score = 0.0
            var reasons: [RecommendationReasonCode] = []
            if coldStart { score += 1; reasons.append(.coldStartDiversity) }
            if let affinity = profile.trackAffinities[track.id] {
                let decay = timeDecay(from: affinity.lastUpdatedAt, to: now)
                let completion = Double(affinity.completions) * 2
                let skip = Double(affinity.skips) * 2
                let listening = min(Double(affinity.listenedMilliseconds) / 3_600_000, 3)
                let exposure = log1p(Double(affinity.exposures)) * 0.2
                let value = (completion + listening - skip - exposure) * decay
                score += value
                if value > 0 { reasons.append(.trackAffinity) }
                if affinity.completions > 0 { reasons.append(.completionHistory) }
            }
            applyContextFeature(for: track.id, profile: profile, now: now, score: &score, reasons: &reasons)
            applyFeature("artist:\(normalize(track.artist))", reason: .artistAffinity, profile: profile, now: now, score: &score, reasons: &reasons)
            if let album = track.album { applyFeature("album:\(normalize(album))", reason: .albumAffinity, profile: profile, now: now, score: &score, reasons: &reasons) }
            for genre in track.genres ?? [] { applyFeature("genre:\(normalize(genre))", reason: .genreAffinity, profile: profile, now: now, score: &score, reasons: &reasons) }
            if let language = track.language { applyFeature("language:\(normalize(language))", reason: .languageAffinity, profile: profile, now: now, score: &score, reasons: &reasons) }
            if let year = track.releaseYear { applyFeature("era:\((year / 10) * 10)", reason: .eraAffinity, profile: profile, now: now, score: &score, reasons: &reasons) }
            if offlineTrackIDs.contains(track.id) { score += 0.5; reasons.append(.availableOffline) }
            score += deterministicUnit(seed: seed, id: track.id) * (coldStart ? 0.8 : 0.25)
            reasons.append(.exploration)
            candidates.append(RecommendedTrack(track: track, score: score, reasons: Array(Set(reasons)).sorted { $0.rawValue < $1.rawValue }))
        }
        candidates.sort { $0.score == $1.score ? $0.track.id.uuidString < $1.track.id.uuidString : $0.score > $1.score }
        return RecommendationResult(engineVersion: version, generatedAt: now, items: diversify(candidates, limit: limit), trace: .init(mode: .heuristic, featureVersion: "heuristic-features-1"))
    }

    public static func fallback(tracks: [TrackSummary], limit: Int, now: Date, seed: UInt64, timedOut: Bool) -> RecommendationResult {
        let eligible = tracks.sorted { deterministicUnit(seed: seed, id: $0.id) > deterministicUnit(seed: seed, id: $1.id) }
        let items = eligible.map { RecommendedTrack(track: $0, score: 0, reasons: timedOut ? [.timeoutFallback, .coldStartDiversity] : [.coldStartDiversity]) }
        return RecommendationResult(engineVersion: version, generatedAt: now, items: diversify(items, limit: limit), usedFallback: timedOut, trace: .init(mode: .fallback, featureVersion: "heuristic-features-1", fallbackCode: timedOut ? "ranking_timeout" : nil))
    }

    public static func policyRerank(_ candidates: [RecommendedTrack], limit: Int) -> [RecommendedTrack] { diversify(candidates, limit: limit) }

    private static func applyFeature(_ key: String, reason: RecommendationReasonCode, profile: RecommendationProfile, now: Date, score: inout Double, reasons: inout [RecommendationReasonCode]) {
        guard let aggregate = profile.featureAggregates[key], aggregate.exposures > 0 else { return }
        let completionRate = Double(aggregate.completions) / Double(aggregate.exposures)
        let listening = min(Double(aggregate.listenedMilliseconds) / Double(max(aggregate.exposures, 1)) / 600_000, 1)
        let value = (completionRate * 1.2 + listening * 0.4) * timeDecay(from: aggregate.lastUpdatedAt, to: now)
        if value > 0 { score += value; reasons.append(reason) }
    }

    private static func applyContextFeature(for trackID: UUID, profile: RecommendationProfile, now: Date, score: inout Double, reasons: inout [RecommendationReasonCode]) {
        let track = trackID.uuidString.lowercased()
        let time = timeBucket(profile.localHour)
        let candidates: [(String, RecommendationReasonCode)] = [
            ("activity:\(profile.activity.rawValue)|time:\(time)|track:\(track)", .contextAffinity),
            ("activity:\(profile.activity.rawValue)|track:\(track)", .activityAffinity),
            ("time:\(time)|track:\(track)", .timeAffinity)
        ]
        for (key, reason) in candidates where profile.featureAggregates[key] != nil {
            applyFeature(key, reason: reason, profile: profile, now: now, score: &score, reasons: &reasons)
            return
        }
    }

    private static func diversify(_ candidates: [RecommendedTrack], limit: Int) -> [RecommendedTrack] {
        var selected: [RecommendedTrack] = [], deferred: [RecommendedTrack] = []
        var albumCounts: [String: Int] = [:], genreCounts: [String: Int] = [:]
        for candidate in candidates {
            let artist = normalize(candidate.track.artist)
            let album = candidate.track.album.map(normalize)
            let genre = candidate.track.genres?.first.map(normalize)
            let repeatsArtist = selected.last.map { normalize($0.track.artist) == artist } ?? false
            let exceedsAlbum = album.map { albumCounts[$0, default: 0] >= 2 } ?? false
            let exceedsGenre = genre.map { genreCounts[$0, default: 0] >= max(4, limit / 3) } ?? false
            if repeatsArtist || exceedsAlbum || exceedsGenre { deferred.append(candidate); continue }
            selected.append(candidate)
            if let album { albumCounts[album, default: 0] += 1 }
            if let genre { genreCounts[genre, default: 0] += 1 }
            if selected.count == limit { return selected }
        }
        for candidate in deferred where selected.count < limit {
            if selected.last.map({ normalize($0.track.artist) == normalize(candidate.track.artist) }) == true { continue }
            selected.append(candidate)
        }
        if selected.count < limit {
            for candidate in deferred where selected.count < limit && !selected.contains(where: { $0.id == candidate.id }) { selected.append(candidate) }
        }
        return selected
    }

    private static func normalize(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    public static func timeBucket(_ hour: Int) -> String {
        switch min(max(hour, 0), 23) {
        case 0..<5: "night"
        case 5..<12: "morning"
        case 12..<17: "afternoon"
        default: "evening"
        }
    }
    private static func timeDecay(from: Date, to: Date) -> Double { exp(-max(to.timeIntervalSince(from), 0) / (90 * 86_400)) }
    private static func deterministicUnit(seed: UInt64, id: UUID) -> Double {
        var hash = seed ^ 0xcbf29ce484222325
        for byte in id.uuidString.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return Double(hash % 1_000_000) / 1_000_000
    }
}
