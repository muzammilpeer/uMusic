# Sprint 20 Report

Status: **Real MERT backend analysis deployed and synchronized; iPhone embedding-aware personalization remains in progress**

Date: 2026-08-11

## Delivered

- Added a versioned backend `TrackAnalysis` record with source checksum, provider/model
  provenance, state, attempts, scalar features, bounded binary embedding, structured error,
  and timestamps.
- Added an idempotent Celery task and safe `backfill_track_analysis` command with limit,
  explicit track IDs, and dry-run support.
- Added a deterministic development provider that creates a normalized 64-component
  Float16 contract fixture from an existing checksum. It does not read audio and its
  values must not be treated as musical facts.
- Added optional owner-scoped `song_features` to `/api/v2/library/changes`. Results are
  emitted only for succeeded analysis matching the current audio checksum.
- Added immutable Swift song-feature types, defensive decoding, bounded validation, and
  atomic Core Data persistence. Missing features preserve the last compatible local value.
- Preserved the existing private Core ML + local telemetry recommendation path and its
  deterministic heuristic fallback. The fake features are intentionally not used to alter
  recommendations.
- Added the model provenance/licensing gate; the initial fake-provider tests used neither
  MERT weights nor private audio before the separately authorized deployment began.
- Added an isolated MERT analysis image and single-concurrency Celery queue with a persistent
  model cache, read-only media access, bounded excerpts, and four CPU threads.
- Installed pinned `m-a-p/MERT-v1-95M` revision
  `12af15fef9d0ac838c3f475bfbbf26d2060dd4f5` outside Git under the owner's explicit
  private/noncommercial authorization.
- Applied migration `library.0006_trackanalysis`, deployed the web and analysis services,
  passed a one-song canary, and analyzed all 67 active songs successfully.

## Schema and API changes

- Django migration: `library.0006_trackanalysis`.
- Catalog API adds optional `song_features`; this is additive for older clients.
- The dynamically constructed Core Data catalog model adds optional binary `songFeatures`
  and uses inferred lightweight migration.

## Validation evidence

- `python3 -m compileall -q umusic config`: passed.
- `docker compose build web`: passed; local image only, not deployed.
- `docker compose run --rm web python manage.py makemigrations --check --dry-run`: passed,
  no missing migrations.
- `docker compose run --rm web python manage.py test umusic.apps.library.tests.test_v2_library_api`:
  passed 5/5 including bounded owner-isolated song features.
- `swift test --package-path umusic-v2.0`: the new feature persistence/validation test and
  other functional tests passed. Overall run: 129 tests with one pre-existing
  `HostProjectTests` case reporting three bundle-identifier expectation issues in the
  already-modified Xcode project.
- Generic iOS `UMusic` build with signing disabled: passed.
- `git diff --check` and Python compile validation: passed.
- Real MERT canary completed in 12.89 seconds including model initialization. Its vector
  was finite, L2-normalized, 64-dimensional, 128 bytes, and source-checksum matched.
- Full backfill completed 67/67 with zero failed records. All vectors are finite,
  64-dimensional, 128-byte Float16 payloads and match current audio checksums.
- The API serializer produced `song_features` for every active membership (134 membership
  rows across the private multi-user catalog, backed by 67 unique analyzed tracks).
- After completion, the analysis worker used about 1.13 GiB and the web container about
  136 MiB. The public readiness endpoint reported healthy database and Redis checks.
- Recorded SHA-256 hashes for all five cached checkpoint/config/code artifacts, enabled
  local-files-only loading, and passed a post-restart offline-cache canary in 3.57 seconds.
- The idempotent backfill dry-run reports zero pending songs after the completed 67-track
  analysis; `--force` remains available for an explicit reanalysis.

## Privacy and operational state

No model weights, MP3 content, production embeddings, credentials, or listening telemetry
were committed to Git. Under explicit owner authorization, the pinned noncommercial MERT
checkpoint was cached in a dedicated Docker volume, production MP3s were processed locally,
compact embeddings were persisted, the additive migration was applied, and the web plus
analysis services were deployed. No media/database volume was deleted or recreated.

## Remaining Sprint 20 work

- Add stronger timeout/OOM mapping, supersession/cancellation, calibrated optional tag
  heads, administrative progress UI, and repeatable Mac mini throughput measurements.
- Add an embedding-aware local preference learner and shared training/inference feature
  manifest. The deterministic fixture must never train or score recommendations.
- Extend research export/evaluation metrics and verify retention/Reset Learning across the
  new learner state.
- Repair or reconcile the unrelated host-project bundle identifier expectations, then run
  the completely green Swift suite and physical-device performance/energy tests.
