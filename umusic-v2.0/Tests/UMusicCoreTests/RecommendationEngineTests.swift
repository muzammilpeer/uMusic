import Foundation
import Testing
import UMusicDomain
import UMusicLearning

private func recommendationTrack(_ value: Int, artist: String, album: String? = nil, genre: String? = nil, language: String? = nil, year: Int? = nil) -> TrackSummary {
    let id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255), 0, 0, 0, 1))
    return TrackSummary(id: id, title: "Track \(value)", artist: artist, durationSeconds: 180, album: album, genres: genre.map { [$0] }, language: language, releaseYear: year)
}

@Test("Cold start is deterministic, diverse, and explanation-backed")
func recommendationColdStartGolden() {
    let tracks = (0..<40).map { recommendationTrack($0, artist: "Artist \($0 % 8)", album: "Album \($0 % 12)", genre: ["Rock", "Jazz", "Classical", "Electronic"][$0 % 4], language: ["en", "ur", "ar"][$0 % 3], year: 1980 + $0) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let first = HeuristicRecommendationEngine.rank(tracks: tracks, profile: RecommendationProfile(), offlineTrackIDs: [], excluding: [], limit: 25, now: now, seed: 42)
    let second = HeuristicRecommendationEngine.rank(tracks: tracks.reversed(), profile: RecommendationProfile(), offlineTrackIDs: [], excluding: [], limit: 25, now: now, seed: 42)
    #expect(first.items == second.items)
    #expect(first.engineVersion == second.engineVersion)
    #expect(first.items.count == 25)
    #expect(first.items.allSatisfy { $0.reasons.contains(.coldStartDiversity) && !$0.reasons.isEmpty })
    for pair in zip(first.items, first.items.dropFirst()) { #expect(pair.0.track.artist != pair.1.track.artist) }
}

@Test("Activity, affinity, completion, metadata, and offline evidence produce auditable reasons")
func recommendationContextGolden() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let favored = recommendationTrack(1, artist: "Favored", album: "Album A", genre: "Electronic", language: "en", year: 2022)
    let other = recommendationTrack(2, artist: "Other")
    let trackAggregate = TrackAffinityAggregate(trackID: favored.id, exposures: 3, completions: 3, skips: 0, listenedMilliseconds: 500_000, lastUpdatedAt: now)
    let activityKey = "activity:running|time:evening|track:\(favored.id.uuidString.lowercased())"
    let activity = FeatureAggregate(featureKey: activityKey, exposures: 3, completions: 3, listenedMilliseconds: 500_000, lastUpdatedAt: now)
    let profile = RecommendationProfile(trackAffinities: [favored.id: trackAggregate], featureAggregates: [activityKey: activity], activity: .running, localHour: 19)
    let result = HeuristicRecommendationEngine.rank(tracks: [other, favored], profile: profile, offlineTrackIDs: [favored.id], excluding: [], limit: 2, now: now, seed: 7)
    #expect(result.items.first?.id == favored.id)
    let reasons = result.items.first?.reasons ?? []
    #expect(reasons.contains(.trackAffinity))
    #expect(reasons.contains(.completionHistory))
    #expect(reasons.contains(.contextAffinity))
    #expect(reasons.contains(.availableOffline))
}

@Test("Sparse metadata and explicit exclusions remain safe")
func recommendationSparseMetadataGolden() {
    let tracks = [recommendationTrack(1, artist: "Unknown"), recommendationTrack(2, artist: "Unknown"), recommendationTrack(3, artist: "Known", genre: "Rock")]
    let result = HeuristicRecommendationEngine.rank(tracks: tracks, profile: RecommendationProfile(activity: .focus), offlineTrackIDs: [], excluding: [tracks[0].id], limit: 10, now: Date(), seed: 1)
    #expect(result.items.count == 2)
    #expect(!result.items.contains { $0.id == tracks[0].id })
}

@Test("Timeout fallback is explicit and does not invent learned explanations")
func recommendationFallbackGolden() {
    let result = HeuristicRecommendationEngine.fallback(tracks: [recommendationTrack(1, artist: "A")], limit: 25, now: Date(), seed: 9, timedOut: true)
    #expect(result.usedFallback)
    #expect(result.items.first?.reasons == [.timeoutFallback, .coldStartDiversity])
    #expect(!result.items.first!.reasons.contains(.trackAffinity))
}

@Test("Ramadan preference off introduces no implicit religious inference")
func recommendationRamadanOffGolden() {
    let track = recommendationTrack(1, artist: "Artist", language: "ur")
    let result = HeuristicRecommendationEngine.rank(tracks: [track], profile: RecommendationProfile(), offlineTrackIDs: [], excluding: [], limit: 1, now: Date(), seed: 2)
    #expect(result.items.count == 1)
    #expect(RecommendationReasonCode.allCases.allSatisfy { !$0.rawValue.localizedCaseInsensitiveContains("ramadan") && !$0.rawValue.localizedCaseInsensitiveContains("relig") })
}

@Test("Twenty-five-thousand-track ranking meets the local diagnostic bound")
func recommendationLargeCatalogPerformance() {
    let tracks = (0..<25_000).map { recommendationTrack($0, artist: "Artist \($0 % 700)", album: "Album \($0 % 2_000)", genre: "Genre \($0 % 20)", language: "l\($0 % 5)", year: 1960 + $0 % 66) }
    let clock = ContinuousClock()
    var samples: [Duration] = []
    for seed in 0..<10 {
        samples.append(clock.measure { _ = HeuristicRecommendationEngine.rank(tracks: tracks, profile: RecommendationProfile(), offlineTrackIDs: [], excluding: [], limit: 25, now: Date(timeIntervalSince1970: 1_800_000_000), seed: UInt64(seed)) })
    }
    samples.sort()
    let p95 = samples[Int(Double(samples.count - 1) * 0.95)]
    let components = p95.components
    let p95Milliseconds = Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    print("recommendation_25k_p95_ms=\(p95Milliseconds)")
#if DEBUG
    #expect(p95 < .seconds(1))
#else
    #expect(p95 < .milliseconds(150))
#endif
}
