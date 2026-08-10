# Sprint 9 Report

Status: **Local observation, retention, aggregation, privacy controls, and sanitized export implemented and locally validated**  
Date: 2026-08-09

## Delivered behavior

- One `LocalLearningStore` actor is shared by live playback, Home history, recommendation fallback, and Learning & Privacy settings.
- Schema-versioned playback sessions, compact typed `EventEnvelope` records, context snapshots, observations, consent records, track affinities, and coarse feature aggregates.
- Stable event UUIDs and monotonic sequences with duplicate-ID rejection.
- Playback records semantic started, resumed, paused, seeked, completed, skipped/replaced, and technical-failure transitions. High-frequency playback ticks are never events.
- The active observation receives a crash-safe checkpoint at the existing 15-second playback boundary.
- Events batch at 25 records or 120 seconds in Low Energy Mode, with immediate flush on pause, completion, technical failure, explicit app checkpoint, and export.
- Repeated pause/resume/seek transitions within two seconds coalesce.
- Exposure is counted independently from preference outcomes. Technical failures never increment preference skips.
- Reducers are atomic and idempotent across relaunch through stable reduced-observation IDs and a sequence checkpoint.
- Default 90-day retention plus 7-day, 30-day, one-year, and indefinite options.
- Expiry reduces observations into non-timeline track/activity aggregates before removing raw events, observations, and unused contexts.
- Delete Raw History removes sessions, events, observations, contexts, and history track snapshots while preserving learned aggregates.
- Reset Learning removes both raw history and learned track/feature aggregates while preserving catalog, downloads, queue storage, and manual playlists.
- Home's last-ten-day view now receives locally persisted observations after actual playback.
- Learning & Privacy UI shows counts, controls retention, confirms deletion/reset, creates a sanitized export, and presents the system share sheet.
- Sanitized JSON export excludes credentials, server URL, username, paths, and coordinate fields by construction.
- Schema 0 documents migrate to schema 1. Unknown future schemas are preserved byte-for-byte and blocked from mutation instead of being overwritten.
- Framework version advanced to `2.0.0-alpha.9`; public production API baselines were refreshed.

## Validation

- 70 Swift tests pass.
- Coverage includes crash between checkpoints, duplicate event IDs, reducer restart, clock rollback, coalescing, expiry before deletion, every retention choice, history-delete versus full-reset scope, schema migration, future-schema preservation, technical failure labels, sanitized-field absence, and bounded checkpoint storage.
- The checkpoint fixture remains below 50 KB and creates no playback-tick events.
- Generic iOS and macOS builds pass with code signing disabled.
- Public production symbol-graph baselines pass. SwiftPM continues to emit its known test-bundle graph warning after the required production graphs are successfully checked.

## Boundaries and remaining gates

- Sprint 9 uses an atomically replaced, protected schema-versioned JSON document rather than the planned split Core Data user/telemetry stores. This validates behavior and API boundaries, but migration to indexed Core Data/SQLite storage remains necessary before very large real-world histories.
- Export is one sanitized JSON document, not the final multi-file ZIP research package. ZIP streaming, optional encryption, automatic temporary-file cleanup, and the macOS Data Inspector remain later delivery work.
- Consent records are modeled and persisted, but signal-specific permission controls arrive with Sprint 10 context sources.
- Context currently contains calendar/time-zone fields and coarse activity only. Sprint 10 adds user-controlled route, network, activity, workout, energy, and coarse-place signals.
- The current playback session is process-scoped; explicit long-lived session end policy will be refined with Sprint 10 activity-session lifecycle.
- The 120-second path is covered structurally and by explicit flush behavior; physical-device energy/write-rate measurement over long playback remains a release gate.
- Logout data-disposition orchestration is still separate from the in-app Delete History and Reset Learning controls.
- No backend changes or Docker deployment were required.

## Next sprint entry

Sprint 10 should add manual activity selection first, independently consented context sources, five-second on-demand Core Motion classification on iPhone, event-driven HealthKit summaries, session-scoped coarse location, audio-route/network categories, app Low Energy policy, revocation cleanup, and macOS-safe alternatives without background polling.
