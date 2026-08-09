# uMusic 2.0 Delivery Sprints

Assumption: two-week sprints, iPhone-first, with iPad/macOS compile compatibility from the beginning. Every sprint ends with tests, documentation, accessibility review for touched UI, and performance instrumentation where relevant.

## Phase 0 — Product and engineering foundations

### Sprint 0: Decisions, prototypes, and budgets

- Confirm deployment targets, supported devices, XCFramework consumers, Core Data choice, audio engine constraints, and privacy defaults.
- Prototype AVPlayer restoration/background audio, XCFramework resource loading, background download restoration, and Core ML inference on minimum hardware.
- Establish launch, memory, energy, database, sync, download, and inference budgets.
- Produce ADRs and threat/privacy model.

Exit: feasibility prototypes pass on physical iPhone; open decisions have owners and dates.

### Sprint 1: Workspace and architecture skeleton

- Create Swift package/modules, app targets, share extension target, test targets, lint/format, CI, dependency injection, clocks/IDs/logging, theme tokens.
- Add stable public `UMusicCore` facade and build XCFramework slices.
- Add typed navigation shell and placeholder tabs.

Exit: app and framework build for iOS simulator/device and macOS; dependency-boundary tests pass.

## Phase 1 — Account, catalog, and reliable playback

### Sprint 2: Authentication and configuration

- Onboarding connection flow, URL validation, API bootstrap, Keychain/token refresh, keep-signed-in behavior, logout choices.
- Redacted networking logs and failure UX.

Exit: auth contract tests pass; credentials never appear in database/export/logs.

### Sprint 3: Catalog persistence and manual sync

- Core Data catalog model/migrations, cursor sync, tombstones, background imports, local search indexes, metadata validation.
- Library base screens and deliberate Sync interaction.

Exit: interrupted sync resumes safely; 25k-track import/search meets budget.

### Sprint 4: Playback foundation

- Player coordinator/state machine, media tickets, local/remote source choice, Now Playing system integration, interruptions and route changes.
- Full player and global mini player.

Exit: play/pause/seek/next/previous work from app, Lock Screen, and headset; error recovery tested.

### Sprint 5: Queue and restoration

- Durable queue/snapshot, resume position, manual Play Next/Later/remove/reorder, refill boundary, app/scene lifecycle persistence.
- Now tab queue UI.

Exit: force-quit/relaunch shows prior track immediately and resumes only after user action; manual queue priority is invariant.

## Phase 2 — Offline and complete product navigation

### Sprint 6: Offline download engine

- Background downloads with delegate restoration, checksum/manifest, quota presets/custom entry, network policy, pinned versus rolling cache, LRU utility eviction.
- Downloaded library and storage settings.

Exit: offline playback and task restoration pass airplane-mode and reboot-style tests; pinned files are not evicted.

### Sprint 7: Library, playlists, and search UX

- Songs/albums/artists/genres/era, track actions, manual playlists, local search/filter, deep links.
- Playlist CRUD and optimistic server revision where applicable.

Exit: all primary library journeys work with cached data and VoiceOver/Dynamic Type.

### Sprint 8: Home and 10-day history

- Start Listening hero, resume card, recent context history grouped across 10 days, starter mixes, typed navigation states.
- Empty/offline/error/loading polish and theme switching.

Exit: cold-start and returning-user journeys pass UI tests; no content is obscured by mini player/keyboard.

## Phase 3 — Privacy-preserving learning

### Sprint 9: Session logging and retention

- Event recorder, observations/context snapshots, batching/checkpoints, retention reducer, affinity aggregates, consent records.
- Privacy/retention settings, delete/reset flows.

Exit: crash recovery loses at most checkpoint window; batch/expiry/export fixtures prove schema behavior and storage budget.

### Sprint 10: Context signals

- Manual activity first; opt-in brief Core Motion; event-driven HealthKit workout adapter; coarse session-scoped location; audio route/network/energy categories.
- Permission education and denial/revocation behavior.

Exit: playback works with every permission denied; physical-device energy test meets budget; no default raw coordinate log exists.

### Sprint 11: Heuristic recommendation engine

- Candidate generation, affinity scoring, hierarchical context backoff, diversity/repetition policy, exploration, reason codes, deterministic fallback.
- Start Listening and near-end queue refill integrate locally.

Exit: cold/warm fixtures satisfy constraints under 150 ms p95; ranking failure never blocks playback.

### Sprint 12: Calendar preferences and smart playlists

- Optional Ramadan preference and selected playlist override, locally maintained calendar window/manual correction.
- Smart playlist rules, auto-grow toggle default off, rate limits, audit/undo.

Exit: preference behavior is transparent and reversible; no religion inference; auto additions always explainable/undoable.

## Phase 4 — Model, import, and developer tooling

### Sprint 13: ML dataset and Mac trainer

- Sanitized export, schema manifest, `UMusicDataInspector`, feature builder, chronological splits, baseline metrics.
- Model card template and reproducible training pipeline.

Exit: exported fixture round-trips through inspector/trainer; leakage/privacy review passes.

### Sprint 14: Core ML ranker lifecycle

- Model registry, signed bundle validation, canary, shadow mode, activation/rollback, metrics, heuristic fallback.
- Optional low-cost calibration updates on device.

Exit: model improves agreed offline metrics without violating latency/energy/size budgets; rollback is tested.

### Sprint 15: Share extension and remote import

- URL validation, minimal extension UI, App Group job handoff, shared Keychain access, import-job API/status/deep link.
- Provider/legal error states and extension-safe framework product.

Exit: share from supported apps creates exactly one idempotent job; no telemetry or secret leaks.

### Sprint 16: Export, diagnostics, and visualizer

- Streaming sanitized/full exports, optional encrypted ZIP, share sheet cleanup, diagnostics UI.
- Optional energy-aware accessible visualizer, isolated from playback-critical work.

Exit: large exports do not spike memory; sensitive fields match preview; visualizer produces no measured underruns.

## Phase 5 — Hardening and launch

### Sprint 17: iPad/macOS adaptation and accessibility

- Sidebar/multicolumn layouts, keyboard commands, macOS-supported context adapters, window restoration, inspector handoff.
- Full accessibility/localization audit.

Exit: platform matrix passes; unsupported HealthKit/Core Motion controls do not appear on macOS.

### Sprint 18: Performance, energy, security, migration strategy

- Instruments/MetricKit runs, database/index tuning, network batching, memory/leak audit, threat-model verification, privacy manifest.
- Define optional v1-to-v2 import adapter without mixing source trees or destroying v1 state.

Exit: budgets and security checklist pass on minimum device; migration is copy-first and rollback-safe.

### Sprint 19: Beta and release candidate

- TestFlight cohort, opt-in feedback, crash/energy/playback dashboards, catalog scale tests, backup/restore drills, release documentation.
- Freeze schemas/public framework API; resolve release blockers.

Exit: release gates in `PROJECT_PLAN.md` pass and known limitations are documented.

## Definition of done for every sprint

- Acceptance criteria have automated tests where technically possible.
- No secret or sensitive-field leakage in logs, exports, fixtures, or screenshots.
- New persisted/API fields include schema version, migration, retention, and unknown-value behavior.
- UI includes loading/empty/offline/error/permission-denied states and accessibility labels.
- Main-thread, memory, energy, storage, and network impact are measured for performance-sensitive work.
- Documentation and ADRs reflect decisions; the XCFramework API compatibility check passes.
- No v1 source is modified unless a later migration sprint explicitly authorizes a narrow adapter.

