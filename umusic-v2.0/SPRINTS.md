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

## How to run a sprint

Use one sprint per implementation task. Replace `<N>` in the shared preamble, append the matching sprint prompt below, and explicitly record any user-approved deviations in that sprint's `REPORT.md`. A sprint prompt authorizes changes only inside `umusic-v2.0` unless it specifically names a server contract fixture or a copy-only v1 migration adapter.

### Shared implementation preamble

```text
You are implementing uMusic 2.0 Sprint <N> in /Users/muzammilpeer/Git/uMusic/umusic-v2.0.

Before editing, read the repository AGENTS.md, the uMusic development skill, and only the references it routes to. Then read README.md, PROJECT_PLAN.md, ARCHITECTURE.md, DATA_AND_PRIVACY.md, API_CONTRACT.md, NAVIGATION_AND_UX.md, this sprint definition, all accepted ADRs, and the previous sprint report. Inspect the current v2 worktree and tests. Treat the existing v1 client/backend as read-only reference unless this sprint explicitly permits a narrow integration change.

Create a checklist that maps each sprint acceptance criterion to implementation files and validation. Preserve user data and unrelated edits. Do not add credentials, production tokens, real listening histories, precise locations, or private exports to source, tests, fixtures, logs, or screenshots. Keep domain code independent of SwiftUI and Apple infrastructure. Use actors for mutable services, immutable Sendable public snapshots, explicit dependency injection, cancellable background work, and the minimum main-actor surface.

Implement only the named sprint scope. Add unit, integration, contract, performance, accessibility, or UI tests in proportion to risk. Validate iOS, macOS, the Swift package, XCFramework API compatibility, privacy behavior, and performance budgets when affected. If a platform API cannot provide a requested signal, document the limitation and implement an honest fallback instead of simulating data.

Finish by creating Documentation/Sprints/Sprint-<N>/REPORT.md with: delivered behavior, architecture decisions, files changed, schema/API migrations, privacy impact, measured results, tests run with exact commands, unresolved risks, and the recommended next sprint. Do not mark the sprint complete while an acceptance criterion is untested or knowingly unmet.
```

## Copy-ready sprint prompts

### Sprint 0 prompt — decisions and feasibility

```text
Execute Sprint 0 as a decision-and-feasibility sprint; do not build production UI. Create a decision register, measurable engineering budgets, privacy/threat model, prototype specifications, and ADRs for deployment targets, Core Data versus SwiftData, playback engine, framework packaging/linkage, model delivery, minimum hardware, and macOS launch scope. Every decision must include context, options, tradeoffs, chosen default or Open status, owner, deadline, and consequences.

Define small disposable spike plans for: restoring an AVPlayer queue/position without autoplay; loading a Core ML resource from an XCFramework bundle; restoring background URLSession download tasks; exporting a large Core Data dataset with bounded memory; and ranking 25,000 candidates on the minimum device. Each spike needs inputs, procedure, measurement method, pass/fail threshold, cleanup, and the later sprint it de-risks. Add a release-risk register and a matrix tracing product requirements to planned sprints.

Validate Markdown links, internal consistency, and that no v1 file changed. Sprint 0 passes only when all release-blocking unknowns have an explicit validation plan and no privacy-sensitive feature is enabled by default.
```

### Sprint 1 prompt — workspace and architecture skeleton

```text
Execute Sprint 1 by creating the compilable Swift package, module folders, thin SwiftUI app shell, share-extension-safe product boundary, test targets, CI commands, dependency rules, composition root, theme tokens, and typed navigation placeholders. Establish UMusicCore's stable public facade using Sendable value snapshots and AsyncSequence state, without exposing AVPlayer, Core Data, Keychain, SwiftUI, or model tensors.

Add automated architecture tests that reject forbidden imports/dependency directions, an API symbol-graph baseline, deterministic Clock/ID/Random test doubles, redacted logging, and resource lookup tests for framework bundles. Build device/simulator/macOS XCFramework slices and document integration into the app target.

Do not implement authentication, real networking, persistence, or playback beyond compile-safe protocols/fakes. Pass Swift tests, iOS/macOS builds, framework creation, API compatibility baseline, and a launch smoke test.
```

### Sprint 2 prompt — authentication and server configuration

```text
Execute Sprint 2 by implementing onboarding connection UI, HTTPS URL normalization/validation, bootstrap capability negotiation, session creation, access-token expiry, refresh rotation, Keychain storage, Keep Me Signed In semantics, and explicit logout choices. Passwords and tokens must never enter Core Data, UserDefaults, analytics, exported diagnostics, or interpolated errors.

Model authentication as an actor-owned state machine with offline/expired/revoked/retryable states. Inject network and Keychain protocols. Include certificate/default transport behavior without bypassing Apple security warnings. Show actionable errors with request IDs but redacted endpoints/headers.

Test valid/invalid URLs, token refresh races, cancellation, server capability mismatch, Keychain failures, logout while offline, denied persistence, and log/export redaction. Do not begin catalog sync in this sprint.
```

### Sprint 3 prompt — catalog persistence and deliberate sync

```text
Execute Sprint 3 by implementing the versioned Catalog Core Data store, normalized metadata entities, indexes, migrations, cursor-based changes sync, tombstones, staging/full-resync recovery, and local search. Sync must start only from an explicit user action; cached metadata appears immediately at launch.

Use a LibrarySync actor and background contexts. Validate UUIDs, durations, years, language confidence, unknown enums, checksums, revisions, and relationship integrity. Advance the cursor only after an atomic page commit. Preserve safe historical track snapshots when server media is tombstoned.

Build the base Library browsing states and Sync status UI. Test interrupted/duplicated/out-of-order pages, schema evolution, corrupt fields, cancellation, 25,000-track import/search budgets, and no-network cached startup. Do not add playback or auto-sync.
```

### Sprint 4 prompt — playback foundation

```text
Execute Sprint 4 by implementing one PlaybackCoordinator, its explicit state machine, AVPlayer adapter, stream-ticket resolution, cached-source preference seam, standard Now Playing metadata, remote commands, audio-session interruptions, route changes, and error recovery. Build the full Now screen basics and global mini player with safe-area behavior.

Keep queue policy minimal to a supplied list; durable restoration belongs to Sprint 5. UI must consume throttled immutable playback snapshots while scrubber animation remains local. Support play/pause, next/previous, seek, and plus/minus 15 seconds from app and system controls. Do not claim arbitrary controls can be added to Lock Screen.

Test transition legality, stale callbacks, expired tickets, unavailable files, interruption/resume policy, route loss, main-thread responsiveness, and media-command behavior. Measure startup-to-audible latency and audio underruns.
```

### Sprint 5 prompt — queue, priority, and restoration

```text
Execute Sprint 5 by implementing durable QueueSnapshot/QueueItem storage, manual versus automatic origins, Play Now/Next/Later, remove/reorder, queue refill boundary, track/position snapshots, and scene lifecycle checkpoints. Restore the prior track, queue, cached/remote identity, seek position, and paused intent synchronously enough to show the mini player immediately, but never autoplay on launch.

Manual items must remain ahead of automatic refill and must not be reordered by recommendation logic. Persist meaningful transitions and a 15-second crash checkpoint without turning it into high-frequency telemetry. A Play action issued while media is preparing must be honored once ready.

Test force-quit-style restoration, corrupt/missing files, stale server revisions, manual priority invariants, duplicate tracks, queue exhaustion, background/foreground races, and checkpoint write budgets.
```

### Sprint 6 prompt — offline media and quota

```text
Execute Sprint 6 by implementing one shared DownloadCoordinator and cache index, background URLSessionDownloadDelegate task restoration, temporary-to-final atomic file commits, checksum/size verification, pinned and rolling states, quota presets/custom limits, Wi-Fi/unmetered default, optional cellular policy, and eviction.

Quota is a hard limit. Never evict pinned or currently playing media. Select rolling candidates using LRU plus predicted utility, reconcile orphaned files, and retain catalog/history after audio deletion. Treat Ethernet as unmetered on macOS and expose charging/network policy truthfully.

Test task restoration, duplicate requests, expired tickets, partial/corrupt downloads, disk-full conditions, concurrent play/evict, quota reduction, airplane mode, app relaunch, and background completion handling. Confirm playback always checks the shared cache before streaming.
```

### Sprint 7 prompt — library, playlists, and search

```text
Execute Sprint 7 by completing Songs, Albums, Artists, Genres, Era, Downloaded, and Playlists navigation; track menus; manual playlist CRUD; optimistic revisions; local debounced search; composable filters; and deep links. Ensure all actions can add to the queue without losing search/navigation state.

Unknown metadata must remain browsable and filterable. Playlist removal must never delete server or offline audio. Server track deletion is not a client capability. Apply Dynamic Type, VoiceOver, keyboard navigation, interactive keyboard dismissal, and mini-player safe-area insets.

Test large-library scrolling/search, duplicate titles, unknown language/year, playlist conflicts, offline mutations, deep links, accessibility labels/order, and every loading/empty/offline/error state.
```

### Sprint 8 prompt — Home, history, and themes

```text
Execute Sprint 8 by building the Start Listening hero, explicit Resume card, last-10-calendar-day history grouped by date and activity/context, starter mixes, status cards, and theme selection. Cold-start content must be useful before learning exists, and history summaries must not reveal precise locations.

Use typed routes and independent tab stacks. Start Listening calls a recommendation protocol that may still be a deterministic stub until Sprint 11. Theme support includes system/light/dark, accent tokens, contrast, Dynamic Type, Reduce Motion, and localization-ready strings.

Test date grouping across time-zone/DST changes, empty and sparse histories, offline launch, restored navigation, theme persistence, Reduce Motion, mini-player overlap, and Home render/scroll performance.
```

### Sprint 9 prompt — local observation, retention, and reset

```text
Execute Sprint 9 by implementing schema-versioned playback sessions, observations, context snapshots, compact EventEnvelope records, actor-owned coalescing/batching, 15-second crash checkpoints, 120-second Low Energy flush, retention presets, aggregate reducers, consent records, delete history, and Reset Learning.

Record semantic transitions only—never playback ticks or continuous sensor samples. Separate technical failures from preference labels, count exposure, retain stable IDs, and make aggregation atomic/idempotent. Expiring raw history may update non-reconstructable affinity aggregates; Reset Learning removes both raw and learned state while preserving catalog/manual playlists unless separately selected.

Test crashes between checkpoints, duplicated event IDs, clock changes, reducer restarts, batch deletes, all retention choices, reset combinations, schema migration, storage/write budgets, and absence of secrets/coordinates.
```

### Sprint 10 prompt — context and permissions

```text
Execute Sprint 10 by implementing manual activity selection first, optional five-second Core Motion sampling in Low Energy Mode, event-driven HealthKit workout summaries, session-scoped coarse location classification, audio route category, network class, and app energy policy. Each source has an independent setting, consent record, permission explanation, lifecycle, and revocation path.

Do not poll GPS every 1–3 minutes, store default coordinate trails, scan BLE for battery values, start sensors by opening a screen, or expose unsupported iPhone sensors on macOS. Indoor activity uses no GPS; missing signals become unknown and never block playback or sync.

Test every permission denied/restricted/revoked, manual overrides, sensor timeouts, background transitions, route changes, unsupported platforms, cleanup after session end, and physical-device battery/CPU impact.
```

### Sprint 11 prompt — heuristic recommendation engine

```text
Execute Sprint 11 by implementing deterministic candidate generation, hierarchical context backoff, decayed track/artist/album/genre/language/era affinity, exposure-aware scoring, exploration, diversity/repetition constraints, queue coherence, offline utility, and reason codes. Integrate Start Listening and refill when eight of 25 tracks remain.

Cold start must work with no observations. Manual queue items and explicit playlist intent always win. Technical failures must not become dislikes. Use a seeded random source for reproducible tests and a hard timeout/fallback so ranking can never block playback.

Create golden fixtures for cold start, activity/time contexts, sparse metadata, Ramadan preference off, huge libraries, and failure fallback. Measure p95 ranking below the agreed Sprint 0 budget and audit explanation correctness.
```

### Sprint 12 prompt — Ramadan preference and smart playlists

```text
Execute Sprint 12 by adding the explicit Ramadan preference choices (Off, Suggest, Prefer, selected playlist), local calendar-window service with version/manual correction, instant override, smart playlist rules, auto-grow default off, weekly addition caps, approval mode, audit reasons, and undo.

Never infer religion from identity, location, language, catalog, or behavior. Calendar status alone must not force content. Content classification comes from server metadata with confidence/unknown handling. Automatic additions submit final playlist membership only; private contextual reasons remain local.

Test calendar boundary/time-zone/manual correction, missing or deleted selected playlist, preference precedence, mixed-language religious content, rate limits, idempotency, conflicts, audit/undo, and no changes when auto-grow is off.
```

### Sprint 13 prompt — export, inspector, and trainer dataset

```text
Execute Sprint 13 by implementing streaming Sanitized and Full local research exports, schema manifest, bounded-memory JSONL/CSV writers, protected temporary files, cleanup, optional encryption interface, and the read-only macOS UMusicDataInspector. Add a reproducible feature builder, chronological session split, heuristic baselines, and model-card template.

Sanitized exports exclude credentials, server URL, usernames, paths, coordinates, raw HealthKit values, and accessory identifiers. Full export requires an explicit preview and remains local. The inspector must copy/open stores read-only and never mutate the live app database.

Test large exports, cancellation, low disk, schema round-trip, redaction, temporary cleanup, malformed packages, deterministic features, temporal leakage checks, and baseline metrics.
```

### Sprint 14 prompt — Core ML ranker lifecycle

```text
Execute Sprint 14 by integrating a bounded Core ML ranker behind the existing RecommendationEngine, with feature manifest, signed model validation, canary inference, shadow mode, activation, rollback, model/version reason tracing, and automatic heuristic fallback. No cloud inference or autonomous LLM call is permitted.

Keep model resources internal to the framework bundle and validate schema/OS/hardware compatibility. A model must never change manual queue priority, privacy policy, explicit content policy, or Ramadan user choice. Record only local aggregate evaluation needed for comparison.

Test bad signature, corrupt/incompatible model, NaN/extreme features, slow inference timeout, activation rollback, resource lookup in all XCFramework slices, reproducibility, latency, memory, energy, and agreed improvement over baselines.
```

### Sprint 15 prompt — share extension and remote import

```text
Execute Sprint 15 by building the extension-safe UMusicImportClient, minimal share UI, HTTP/HTTPS normalization, supported-provider validation, App Group handoff, shared Keychain token migration, idempotent import-job request, progress state, containing-app deep link, and clear legal/availability failures.

The extension displays the normalized URL and one Send to Server action; it does not download media, invoke playback, collect telemetry, or link unavailable sensor/player APIs. Validate length, scheme, redirects, multiple share representations, cancellation, and unavailable authentication.

Test sharing from representative apps on iOS/macOS, exactly-once job creation, extension memory/time budget, token absence/migration, malicious URL forms, offline retry, redacted logs, and no context payload.
```

### Sprint 16 prompt — diagnostics and optional visualizer

```text
Execute Sprint 16 by completing export/share-sheet lifecycle, sanitized diagnostics UI, schema/model/build display, and an optional visualizer isolated from playback-critical work. The visualizer respects Reduce Motion and Low Energy Mode, throttles rendering, releases resources offscreen, and never requires microphone capture for music already being played.

Diagnostics must use stable error codes and redacted metadata; no secrets, full URLs, file paths, coordinates, or raw health values. Sharing a sensitive Full export requires a clear content preview at action time.

Test large export memory, share cancellation/completion cleanup, diagnostics redaction, visualizer backgrounding, route changes, Reduce Motion, Low Energy Mode, frame/CPU budget, and audio underruns.
```

### Sprint 17 prompt — iPad, macOS, and accessibility

```text
Execute Sprint 17 by adapting the established routes to iPad multicolumn and macOS sidebar/window layouts, keyboard commands, focus behavior, platform menus, window restoration, and inspector handoff. Retain route identity and feature parity where Apple APIs permit it.

Hide unsupported HealthKit/Core Motion controls on macOS; use manual activity and supported location/power/network adapters. Do not create fake data. Complete VoiceOver, Voice Control, Dynamic Type, contrast, Reduce Motion, keyboard-only, localization, and right-to-left layout audits.

Test the platform/device matrix, size classes, multiple windows, external keyboard, long/localized content, empty/error/offline states, mini-player insets, and macOS compile/runtime availability.
```

### Sprint 18 prompt — hardening and safe migration design

```text
Execute Sprint 18 by profiling and tuning launch, main-thread stalls, audio underruns, memory, Core Data queries/indexes/WAL, sync/download network use, battery, and model inference on minimum hardware. Verify threat model, privacy manifest, required-reason APIs, file protection, Keychain access groups, TLS behavior, export cleanup, and dependency vulnerabilities.

Design and test a copy-first optional v1-to-v2 migration adapter that reads supported v1 metadata/settings/history without modifying or deleting v1. Map IDs explicitly, report unsupported fields, checkpoint progress, validate counts/checksums, allow retry, and provide rollback by deleting only the incomplete v2 import after confirmation.

Pass every Sprint 0 budget or document a user-approved revised budget with evidence. Run corruption, interruption, low-storage, offline, permission, and migration recovery drills.
```

### Sprint 19 prompt — beta and release candidate

```text
Execute Sprint 19 as stabilization and release preparation. Freeze public framework/API/persistence schemas, assemble TestFlight with privacy-safe diagnostics, execute scale/backup/restore/offline drills, triage crashes and playback failures, verify model rollback, complete release notes/onboarding/help/known limitations, and produce a signed release checklist.

Do not add new product scope. Fix release blockers with targeted tests; defer non-blockers transparently. Beta feedback collection must be opt-in and must not upload raw personal learning, location, HealthKit, or listening timelines.

Release only when every PROJECT_PLAN release gate is evidenced in the report, all supported platforms build, migrations and rollback pass, crash/playback/energy targets are met, no critical security/privacy issue remains, and the user accepts documented limitations.
```
