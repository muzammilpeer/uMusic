# Sprint 8 Report

Status: **Home, ten-day history contract, deterministic Start Listening, and appearance settings implemented and locally validated**  
Date: 2026-08-09

## Delivered behavior

- Home now provides a useful cold-start surface from the manually synced cached library; it never starts a server sync on launch.
- Start Listening calls the `PersonalizationManaging` recommendation boundary, requests up to 25 tracks, and starts playback through the shared queue coordinator.
- Sprint 8 uses a stable deterministic rotation by track identity and hour. It is intentionally a non-learning implementation until Sprint 11.
- Explicit Continue Listening card resumes the restored track and queue only after the user taps Resume. Restored playback remains paused at launch.
- Starter mixes provide All Music, the first available genre, and recent-era options without requiring listening history.
- Device status cards show cached-library and completed-download counts, plus the last library-sync time or manual-sync guidance.
- Privacy-safe history domain types group the inclusive last ten calendar days by local day and coarse activity. Coordinates and precise place names cannot be represented by the Home history model.
- Home displays empty, sparse, and populated history states. The placeholder history provider remains empty until Sprint 9 records observations.
- Appearance settings persist system/light/dark preference and violet/blue/orange/green accent tokens with `UserDefaults`/`AppStorage`.
- Semantic SwiftUI fonts retain Dynamic Type support. Home transitions honor Reduce Motion.
- Existing typed routes, four independent navigation stacks, and bottom safe-area mini-player behavior remain intact.
- Framework version advanced to `2.0.0-alpha.8`; production public API baselines were refreshed and verified.

## Validation

- 62 Swift tests pass.
- Coverage includes DST/time-zone calendar grouping, ten-day exclusion, empty/sparse histories, deterministic cold start, persisted theme/accent values, Reduce Motion, offline/no-auto-sync source contracts, navigation preservation, and mini-player safe-area behavior.
- A 25,000-track Home starter-mix construction test completed in approximately 0.09 seconds locally, below its two-second bound.
- Generic iOS and macOS `UMusicApp` builds pass with code signing disabled.
- Production public symbol-graph baselines pass. SwiftPM still reports the known test-bundle symbol-graph warning after successfully emitting and checking the required production graphs.

## Boundaries and remaining gates

- Sprint 8 does not learn preferences. The deterministic recommendation stub is an explicit protocol implementation that Sprint 11 will replace.
- Listening history is empty in the live composition until Sprint 9 implements schema-versioned local observations, retention, aggregation, export, and reset.
- Starter mixes are metadata-based entry points, not claims of learned taste.
- Activity names are coarse summaries only. No location collection, permission prompts, HealthKit, or motion sampling is enabled in this sprint.
- Appearance values are persisted device-local and are not synchronized to the backend.
- Physical-device checks at maximum Dynamic Type sizes, VoiceOver, Reduce Motion, and sustained Home scrolling remain release validation gates.
- No backend changes or Docker deployment were required.

## Next sprint entry

Sprint 9 should implement schema-versioned, efficient local listening observations; semantic event coalescing; crash checkpoints; low-energy batching; retention presets; aggregate reduction; export; delete history; and Reset Learning without continuous sampling or storing secrets/coordinates.
