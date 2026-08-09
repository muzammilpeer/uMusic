# Sprint 14 progress report

- Status: complete
- Started: 2026-08-03
- Completed and deployed: 2026-08-03

## Implemented foundation

- Added owner-scoped `LibraryMembership` records with active/removed state, source,
  timestamps, a unique owner/track constraint, and an owner/state index.
- Added per-user logical storage quotas and usage calculation.
- Imports now create or reactivate membership for both new and checksum-deduplicated
  MP3 files, and reject additions that exceed the importing user's quota.
- Added an idempotent `backfill_library_memberships` command. It is dry-run by default
  and requires both an explicit username and `--apply` before writing.
- Filtered the core web/API catalog, artist/album lists, stream access, playback queues,
  events, playlists, recommendation candidates, taste matching, sync manifests, and
  signed downloads by active owner membership.
- Disabled users can no longer authenticate with an otherwise valid device token.
- Removing a song now removes only the requesting user's membership and playlist
  entries. It does not deactivate the catalog track or delete shared physical media.
- Added Django admin support for user quota/status/password management and audit events.
- Added a two-user regression suite covering catalog visibility, UUID detail/stream
  isolation, playback/event rejection, device-bound downloads, quota enforcement,
  disabled users, and safe single-user membership removal.

## Verification completed

- Python compilation passed.
- Migration drift check reports no changes.
- All migrations apply successfully to a clean disposable database.
- The initial two-user isolation suite passes: 5 tests.
- A backend image was built for validation but was not applied to the running service.

## Production migration and verification

- Created `/backups/pre-sprint14-20260803` before applying migrations.
- Isolated restore installed 2,840 fixture objects and verified all active media. Eight
  intentionally inactive historical tombstones have no MP3 object; no active media is missing.
- Production impact was one active owner, 66 active tracks, and eight inactive tracks.
- Dry run reported 66 missing memberships; apply created exactly 66; the repeat dry run
  reported 66 existing and zero missing.
- Full backend suite: 94 passed. Ruff passed. Strict mypy passed after final typing fixes.
- iOS and macOS generic builds passed. Django check and readiness passed.
- Web, worker, and scheduler were rebuilt and recreated; PostgreSQL, Redis, media,
  quarantine, and backup volumes were preserved.

## Sprint 15 readiness

Sprint 14's membership, isolation, backup, migration, and deployment gates are satisfied.
Sprint 15 may add explicit playlist sharing without exposing personal learning or context data.
