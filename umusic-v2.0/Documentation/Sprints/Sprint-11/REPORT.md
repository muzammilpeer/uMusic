# Sprint 11 Report

Status: **Deterministic heuristic recommendations and automatic queue refill implemented and locally validated**  
Date: 2026-08-09

## Delivered behavior

- `HeuristicRecommendationEngine` ranks the cached catalog entirely on device with stable seeded exploration and deterministic tie-breaking.
- Cold start produces a diverse queue without observations or complete metadata.
- Warm ranking applies time-decayed track evidence, completion/skip/listening history, exposure penalty, and artist, album, genre, language, and decade affinities.
- Context uses an explicit hierarchical backoff: activity plus time bucket, then activity, then time, followed by broader track and metadata evidence.
- Offline-ready tracks receive a bounded utility bonus without excluding streamable tracks.
- Every recommendation carries typed, auditable reason codes; timeout fallback is identified explicitly and never invents learned reasons.
- Diversity prevents adjacent same-artist tracks where the candidate set permits it, caps album repetition, and limits dominant genres before a relaxed fill preserves queue length.
- Ranking cooperatively observes cancellation and is raced against a 100 ms deadline. A deterministic fallback queue ensures ranking cannot block playback.
- Home's **Start Listening** action now requests 25 ranked tracks and marks them as automatic queue entries.
- Playback requests a refill when eight or fewer upcoming tracks remain and fills toward 25 without duplicate track IDs.
- Explicit manual next/later items remain ahead of automatic refill items; manual playlist and library play actions retain manual origin.
- Technical playback failures remain exposure events and are not converted into preference skips.
- Framework version advanced to `2.0.0-alpha.11`; the resource manifest and public API baselines were refreshed.

## Validation

- 84 Swift tests pass in debug configuration.
- Golden coverage includes deterministic cold start, activity/time context, affinity and completion evidence, offline utility, sparse metadata, explicit exclusions, Ramadan preference off, timeout fallback, automatic refill, and manual queue priority.
- A 25,000-track optimized ranking benchmark measured **70.8 ms p95** across ten seeded runs, below the Sprint 0 release gate of 150 ms.
- Generic iOS and macOS `UMusicApp` builds pass with code signing disabled.
- Public production symbol-graph baselines pass. SwiftPM still emits the known test-bundle symbol-graph warning after validating the required production graphs.

## Boundaries and remaining gates

- The engine is a transparent heuristic baseline. Core ML model packaging, training, evaluation, and rollback begin in later sprints.
- Recommendation result reasons are returned in memory; a durable recommendation-decision audit stream is not yet added to the Sprint 9 learning document.
- The performance result is a local optimized macOS diagnostic. The release gate still requires measurement on supported physical iPhone hardware with representative persisted history.
- Context aggregates use coarse time buckets and activity labels only. No identity, raw location, religion, or sensitive catalog inference is introduced.
- Ramadan preference remains off-neutral in Sprint 11. Explicit calendar preferences and reversible smart-playlist behavior belong to Sprint 12.
- No backend changes or Docker deployment were required; the backend remains catalog, metadata, playlist, ticket, and import infrastructure rather than a recommendation service.

## Next sprint entry

Sprint 12 should add explicit Off/Suggest/Prefer Ramadan choices, selected-playlist override, a versioned local calendar window with manual correction, and reversible smart-playlist rules with auto-grow off by default, weekly caps, approval mode, audit reasons, and undo—without inferring religion.
