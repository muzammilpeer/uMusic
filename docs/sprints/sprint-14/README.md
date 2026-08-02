# Sprint 14 — Multi-user accounts and private libraries

## Goal

Convert the single-owner installation into a safe multi-user system where every
person has an independent library, devices, history, recommendations, contexts,
workouts, offline plans, quotas, and account lifecycle.

## Design decisions

- Keep `Track`, `AudioFile`, `Artist`, `Album`, and artwork as deduplicated server
  catalog objects.
- Add an owner-scoped library-membership model instead of duplicating MP3 files.
- A track is visible or playable only through an active membership or an explicit
  share introduced in Sprint 15.
- Imports create membership for the importing user, including duplicate-file imports.
- Listening, learning, context, device, playback, sync, and recommendation records
  remain strictly owner-scoped.
- Removing a song from one library removes only that membership. Physical media is
  eligible for administrator cleanup only when it has no memberships, playlist
  references, active shares, or other protected references.
- Existing data migrates to the current owner without losing files, playlists,
  events, recommendations, or offline manifests.

## Deliverables

- User administration in Django for create, disable, reactivate, and password reset.
- `LibraryMembership` (or equivalent) with owner, track, state, source, timestamps,
  and a unique owner/track constraint.
- Per-user storage quota and current logical usage reporting. Shared physical files
  count once per user's accessible library without multiplying disk consumption.
- Owner-filtered track list/detail/stream/download/import/delete, web portal, search,
  playlists, playback sessions, sync plans, continuations, and recommendation inputs.
- Device tokens bound to exactly one user; logout/revocation affects only that device.
- Migration/backfill command with dry-run, counts, idempotency, and rollback guidance.
- Web and SwiftUI account/library behavior that requires no automatic library sync;
  users still press Sync explicitly.
- Audit events for membership additions/removals, quota changes, user status changes,
  and denied cross-user access.
- Privacy export/deletion updated to include only the requesting user's relationships
  and personal data while retaining shared catalog media required by other users.

## Security and test matrix

- Use an explicit two-user fixture in API tests.
- For every UUID endpoint, prove user A cannot list, fetch, stream, download, mutate,
  delete, queue, sync, or infer user B's private track; return 404 where disclosure
  would reveal existence.
- Test duplicate MP3 import by two users, single-user removal, final-reference cleanup,
  disabled users, revoked devices, quota exhaustion, export, and account deletion.
- Test all background jobs with captured owner IDs and owner-filtered querysets.
- Verify database constraints and avoid relying only on view-level filtering.

## Out of scope

- Playlist sharing and collaboration (Sprint 15).
- Public profiles, public links, chat, comments, followers, or social feeds.
- Automatic access to another user's listening, fitness, location, or taste data.

## Exit criteria

- Existing single-owner production data is migrated without loss.
- At least two users can import the same MP3 without duplicating the physical object.
- Each user sees only their own library and personalized data.
- Cross-user authorization tests cover every relevant API and web endpoint.
- Removing one membership never breaks another user's playback or offline manifest.
- Backup and isolated restore succeed after the new migration.
- Django tests, Ruff, mypy, migration-drift check, readiness, iOS build, and macOS
  build pass.

## Start

Use [PROMPT.md](PROMPT.md).
