# Development prompts

These prompts are intended to start implementation one sprint at a time. Run each
prompt only after the preceding sprint satisfies its exit criteria. The developer
or coding agent must inspect the current repository and preserve existing work.

## Common prefix for every sprint

```text
You are implementing uMusic, a private self-hosted context-aware MP3 player.
Read README.md and every file under docs/ before changing code. Inspect the current
repository and git status. Implement only the requested sprint, preserving prior
contracts and unrelated work. Use a modular Django monolith, PostgreSQL, Redis,
Celery, pytest, and documented migrations. Add tests for security boundaries and
failure paths, update OpenAPI/docs, run the relevant checks, and report exactly
what passed or remains blocked. Never place secrets in Git. Only accept genuine
MP3 audio. Do not implement DRM or access-control bypasses.
```

## Prompt — Sprint 0

```text
Implement Sprint 0 from docs/04-sprint-plan.md. Scaffold the Django project and
domain app packages described in docs/02-architecture.md. Add Docker Compose for
PostgreSQL and Redis, Celery wiring, environment-based settings, pytest, Ruff,
formatting, typing, pre-commit, CI, a dependency-aware health endpoint, an
.env.example, Makefile or equivalent task runner, and developer setup docs.
Choose and pin compatible stable dependency versions. Do not add business models
yet beyond the custom user model if Django requires it before first migration.
Verify a clean database can migrate and all checks pass.
```

## Prompt — Sprint 1

```text
Implement Sprint 1 from docs/04-sprint-plan.md. Create the accounts and library
domain, MP3 upload/import job, quarantine flow, content inspection, SHA-256 storage,
ID3/artwork extraction, exact duplicate handling, audit records, owner-facing web
pages, and REST endpoints. Validate file content rather than extension alone.
Implement a storage interface with local Docker-volume and mounted shared POSIX
filesystem backends suitable for GFS/GlusterFS. Store backend IDs/object keys,
not host absolute paths, and test cross-filesystem publish and concurrent imports.
Design transaction boundaries so failed imports never create active tracks or
orphan permanent files. Add fixtures for valid, corrupt, mislabeled, duplicate,
and oversized inputs without committing copyrighted music.
```

## Prompt — Sprint 2

```text
Implement Sprint 2 from docs/04-sprint-plan.md. Add authenticated HTTP byte-range
streaming with complete integration tests, library/search pages, a persistent web
audio player, queues, playback sessions, Media Session integration, and manual
playlists. The player must survive HTMX navigation and restore queue state after
refresh. Keep production audio delivery compatible with an internal reverse-proxy
redirect while retaining a development fallback.
```

## Prompt — Sprint 3

```text
Implement Sprint 3 from docs/04-sprint-plan.md. Add an append-only, idempotent,
batch listening-event API and update the web player to report reliable events.
Define heartbeat and completion rules explicitly. Build aggregation into derived
play facts without destroying raw events. Test duplicate batches, late events,
clock skew, seeks, replay, early/late skips, browser refresh, and retry behavior.
```

## Prompt — Sprint 4

```text
Implement Sprint 4 from docs/04-sprint-plan.md. Add activities, custom activity
configuration, saved geofences, immutable context snapshots, workout phases, and
the session setup UI. Web users must be able to choose a place manually. Store a
geofence reference in listening context, not raw playback coordinates. Implement
forget-learning and deletion semantics with privacy tests and audit records.
```

## Prompt — Sprint 5

```text
Implement Sprint 5 from docs/04-sprint-plan.md using docs/03-data-and-learning.md.
Build deterministic, versioned signal aggregation for global and contextual
affinities. Include confidence, minimum evidence, time decay, explicit overrides,
full rebuild from the event log, reset controls, Celery scheduling, and an
explainable learning dashboard. Add golden-data tests proving rebuild determinism
and preventing one ambiguous skip from creating a strong negative preference.
```

## Prompt — Sprint 6

```text
Implement Sprint 6 from docs/04-sprint-plan.md. Build eligibility filters,
candidate sources, configurable scoring, penalties, activity energy curves,
duration fitting, sequencing, deterministic seeded generation, immutable playlist
versions, and reason-code explanations. Add UI for generation, regeneration,
track replacement, energy, duration, and discovery. Evaluate results on synthetic
histories for cycling, running, gym, focus, relax, and cold-start users.
```

## Prompt — Sprint 7

```text
Implement Sprint 7 from docs/04-sprint-plan.md. First create a generic, audited,
feature-flagged import adapter interface and a restricted server-folder importer.
Then implement authorized taste-metadata import with a confirmation inbox for
uncertain matches. Finally add an OPTIONAL private YouTube audio adapter using a
maintained Python library or subprocess wrapper. It must be disabled by default,
require an operator attestation that each source is authorized for download,
enforce rate/concurrency/size limits, avoid credentials and restriction bypasses,
record provenance, and pass resulting files through the normal MP3 validation
pipeline. Keep taste import and audio acquisition as separate permissions/jobs.
```

## Prompt — Sprint 8

```text
Implement Sprint 8 from docs/04-sprint-plan.md. Add scheduled and manual smart
playlist refresh, the wanted-track inbox, operational dashboards, retry controls,
responsive accessible web polish, backup/restore management commands, and catalog
performance tests. Demonstrate a restore in an isolated environment and profile
the important queries using a generated 50,000-track dataset.
```

## Prompt — Sprint 9

```text
Implement Sprint 9 from docs/04-sprint-plan.md. Produce production container and
Compose configuration, reverse-proxy audio delivery, health checks, scoped device
tokens, structured logs, rate limiting, backup hooks, and a versioned OpenAPI
contract. Finalize offline manifests, expiring download authorization, checksums,
sync acknowledgement, and idempotent mobile event batches. Add contract fixtures
that a future Swift client can consume and run an HTTPS deployment smoke test.
```

## Prompt — Sprint 10

```text
Implement Sprint 10 from docs/04-sprint-plan.md as a SwiftUI iPhone application.
Follow the frozen OpenAPI contract. Add secure onboarding, Keychain token storage,
library/search/playlists, one playback service, background audio, Now Playing,
Lock Screen/Control Center/headphone controls, queue persistence, and event sync.
Use dependency injection so networking, storage, and audio can be tested. Verify
on a physical iPhone as well as simulator where possible.
```

## Prompt — Sprint 11

```text
Implement Sprint 11 from docs/04-sprint-plan.md. Add session preparation, sync-plan
and manifest handling, background/resumable MP3 downloads, SHA-256 verification,
local metadata/artwork, storage quotas, pinning, Wi-Fi/charging options, immutable
offline queues, and idempotent deferred event upload. Test interruption, app
termination, manifest replacement, low storage, checksum failure, and airplane
mode playback. Add a bounded rolling cache and queue-continuation client: when the
prepared pool is nearly empty and the server is reachable, request more context-
appropriate tracks, stream the immediate next track, and prefetch later tracks.
Test online extension, server timeout, network loss, eviction, and offline fallback.
```

## Prompt — Sprint 12

```text
Implement Sprint 12 from docs/04-sprint-plan.md. Add workout modes for cycling,
running, gym, walking, focus, and custom activities; optional geofence resolution;
optional HealthKit workout integration; phase transitions; and bounded on-device
reranking of only future tracks. Permission denial must preserve manual context.
Optimize for locked-screen reliability, low battery use, privacy, large touch
targets, and minimal interaction during exercise. Do physical-device field tests.
```

## Prompt — Sprint 13

```text
Implement Sprint 13 from docs/04-sprint-plan.md. Build evaluation views comparing
model versions and activity outcomes, then run a quality pass across crashes,
battery, sync, playback, privacy, and authentication. Add data export/deletion,
complete the threat model and runbook, and execute the release checklist. Do not
declare success unless the complete server-to-airplane-mode-workout journey and a
backup/restore exercise both pass.
```
