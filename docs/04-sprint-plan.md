# Sprint plan

Assume two-week sprints for one developer. Each sprint must end with runnable
software, tests, migration review, and updated documentation. Do not begin iOS
until the backend API and recommendation contract meet the Sprint 9 exit gate.

## Sprint 0 — Repository and engineering foundation

**Goal:** establish a repeatable Django development environment.

Deliverables:

- Django project and modular app skeleton.
- PostgreSQL, Redis, Celery, and local mail/log configuration.
- Docker Compose development environment.
- Environment-variable settings and example configuration.
- Ruff, formatter, type checking, pytest, coverage, and pre-commit hooks.
- CI for lint, tests, migrations, and dependency checks.
- Architecture decision records and contribution guide.

Exit criteria:

- A new checkout starts with documented commands.
- Health endpoint confirms database and Redis connectivity.
- CI passes from an empty database.

## Sprint 1 — Accounts, library domain, and MP3 ingestion

**Goal:** upload, validate, store, and browse MP3 files safely.

Deliverables:

- Custom Django user model and single-owner bootstrap.
- Track, artist, album, artwork, audio-file, import-job, and audit models.
- Quarantine and checksum-addressed storage.
- Storage abstraction supporting a local Docker volume and a Docker-mounted
  GFS/GlusterFS-style shared filesystem.
- MP3-only ffprobe validation and ID3 extraction.
- Duplicate detection and transactional import.
- Admin/library pages and upload API.
- Import failure UI with actionable messages.

Exit criteria:

- Valid MP3 uploads appear in the library.
- Renamed non-MP3 content is rejected.
- Duplicate bytes do not create duplicate stored files.
- Corrupt uploads cannot enter active storage.

## Sprint 2 — Backend streaming and web player

**Goal:** make the backend a usable music player.

Deliverables:

- Authorized byte-range streaming endpoint.
- Library browse, search, album, artist, and track pages.
- Persistent bottom web player.
- Queue management and playback-session records.
- Media Session controls where browsers support them.
- Manual playlists and playlist editor.

Exit criteria:

- Seeking and resume work on large files.
- Refreshing/navigating does not lose the current queue.
- Unauthorized users cannot stream by guessing URLs.

## Sprint 3 — Reliable listening telemetry

**Goal:** create trustworthy learning data.

Deliverables:

- Append-only listening-event API.
- Client-generated idempotency IDs and batch ingestion.
- Playback progress heartbeat policy.
- Derived play facts: completion, early skip, replay, listening time.
- User feedback controls.
- Event inspection/admin screen and retention policy.

Exit criteria:

- Duplicate client batches do not duplicate events.
- A web listening session reconstructs accurately after refresh.
- Automated tests cover seeks, short plays, completion, and offline ordering.

## Sprint 4 — Activities, geofences, and contextual sessions

**Goal:** let the user explicitly describe the listening situation.

Deliverables:

- Activity presets and custom activities.
- Named geofence/place CRUD with privacy settings.
- Manual place selection in the web player.
- Context snapshots and workout/session phase definitions.
- Session setup screen: activity, place, duration, energy, discovery.
- Context-aware listening history filters.

Exit criteria:

- Every new session can carry an immutable context snapshot.
- Events store geofence IDs, not raw coordinates by default.
- Deleting/forgetting a place removes its learned associations safely.

## Sprint 5 — Learning engine version 1

**Goal:** turn listening behavior into explainable preferences.

Deliverables:

- Configurable/versioned signal weights.
- Aggregation jobs for track, artist, genre, activity, place, and time affinities.
- Confidence and minimum-evidence rules.
- Time decay for implicit evidence.
- User controls to reset, edit, or rebuild learning.
- Learning dashboard showing why affinities exist.

Exit criteria:

- Rebuilding from the event log is deterministic.
- Explicit dislikes always override positive implicit signals.
- No context affinity is treated as strong from one ambiguous skip.

## Sprint 6 — Playlist generator and sequencing

**Goal:** generate useful activity playlists from learned data.

Deliverables:

- Candidate generation, scoring, penalties, and reason codes.
- Duration-aware sequencing and activity energy curves.
- Artist/album spacing and recently-played controls.
- Familiarity/discovery slider.
- Immutable generated-playlist versions.
- “Regenerate,” “replace this track,” and explanation UI.

Exit criteria:

- A requested duration is met within one average track length.
- The same inputs/model/seed reproduce the same playlist.
- Each chosen track exposes at least one explanation.

## Sprint 7 — Taste imports and MP3 source adapters

**Goal:** expand preference data and make acquisition modular.

Deliverables:

- Generic import-adapter interface and feature flags.
- Direct server-folder MP3 import restricted to configured roots.
- Authorized playlist/export metadata import and matching inbox.
- Exact, probable, unmatched, and rejected matching states.
- Optional private YouTube audio adapter with operator attestation, audit trail,
  rate limits, concurrency limits, and MP3 validation.
- Clear separation of taste metadata from audio acquisition permission.

Exit criteria:

- Disabling an adapter removes its UI and job entry points.
- Every acquired file passes the Sprint 1 pipeline.
- Uncertain metadata matches require confirmation.
- No adapter contains DRM or access-control bypass behavior.

## Sprint 8 — Scheduled intelligence and web product polish

**Goal:** make uMusic pleasant for daily backend/web use.

Deliverables:

- Scheduled playlist refresh and manual “sync collection” action.
- Wanted/missing-track inbox.
- Storage, import, worker, and recommendation health dashboards.
- Responsive web UI and accessibility pass.
- Backup/restore commands and documented disaster test.
- Performance profiling for a 50,000-track catalog.

Exit criteria:

- The web product can be used daily without Django admin.
- Scheduled work is observable and retryable.
- A tested restore recreates database and media references.

## Sprint 9 — Production deployment and mobile API freeze

**Goal:** deploy safely and stabilize contracts for iOS.

Deliverables:

- Production Docker images and Compose file.
- HTTPS/reverse proxy documentation and internal audio redirect.
- Device registration and scoped token authentication.
- Versioned REST API schema and generated client fixtures.
- Rate limiting, structured logs, metrics, and health checks.
- Offline manifest, checksum, and event-sync API contracts.

Exit criteria:

- Production smoke test passes behind HTTPS.
- Mobile contract tests pass.
- Backup/restore and token revocation are demonstrated.
- Recommendation API p95 is below the agreed target.

## Sprint 10 — SwiftUI app foundation and online playback

**Goal:** browse and play the backend library on iPhone.

Deliverables:

- SwiftUI application, dependency boundaries, and secure server onboarding.
- Library/search/playlist screens.
- Audio playback service and queue.
- Background audio, Lock Screen, Control Center, and headphone commands.
- Listening-event capture and API synchronization.

Exit criteria:

- Audio continues with the screen locked.
- Remote commands behave consistently.
- Device token can be revoked from the web portal.

## Sprint 11 — Offline manifests and pre-workout sync

**Goal:** prepare and play a full session without internet.

Deliverables:

- Session preparation and generated playlist request.
- Manifest diff, resumable downloads, checksums, and storage quota.
- Offline prepared pool, bounded rolling cache, pin/eviction rules, and cache
  visibility in the app.
- Queue continuation API usage when the remaining playable pool falls below its
  threshold; stream the immediate track and prefetch later tracks.
- Wi-Fi-only and charging preferences.
- Offline database, artwork cache, and immutable queue.
- Deferred event batch and conflict-free reconciliation.

Exit criteria:

- A prepared playlist plays in airplane mode.
- Interrupted downloads resume without corrupt files.
- Offline events upload once and only once.
- Exhausting the prepared pool extends playback when online and degrades cleanly
  to remaining cached tracks when offline.

## Sprint 12 — Workout and place intelligence on iPhone

**Goal:** apply activity and place context safely during real workouts.

Deliverables:

- Cycling, running, gym, walking, and focus session UI.
- Optional Core Location geofence resolution.
- Optional HealthKit workout save/integration.
- Workout phase transitions and on-device next-track reranking.
- Minimal, glanceable Now Playing experience.
- Battery, privacy, and field-test dashboard.

Exit criteria:

- A real cycling/running test completes with locked-screen playback.
- Playback never requires connectivity after preparation.
- Location denial leaves manual context fully functional.
- Raw route storage remains opt-in.

## Sprint 13 — Field learning and quality release

**Goal:** validate that the system improves personal listening.

Deliverables:

- Multi-week evaluation report by activity.
- Model-version comparison.
- Crash, battery, sync, and skip-rate fixes.
- Data export/delete controls.
- Security review and threat-model update.
- Version 1 runbook and release checklist.

Exit criteria:

- No critical data-loss, playback, privacy, or authentication defects.
- Recommendation metrics improve or a documented fallback is selected.
- The full server-to-offline-workout journey is repeatable.
