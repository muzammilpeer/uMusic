# Sprint 14 implementation prompt

```text
Implement Sprint 14 of uMusic: multi-user accounts and strictly private libraries.
Read AGENTS.md and the uMusic development skill first. Inspect the existing ownership
model and preserve all production data and unrelated edits.

Keep Track/AudioFile metadata and physical MP3 storage deduplicated. Introduce an
owner-scoped library-membership model and backfill every existing track to the current
owner using an idempotent, observable migration or management command with a dry run.
Imports, including duplicate-checksum imports, must create membership for the importer.

Enforce ownership across the track catalog, search, detail, streaming, signed download,
metadata editing, removal, playlists, playback sessions, sync plans/manifests,
continuations, contexts, events, recommendations, web portal, privacy export/deletion,
Celery tasks, and Apple API responses. A user probing another user's private UUID must
receive 404. Never share listening, workout, HealthKit, location, context, or learning
data. Bind every device token and offline plan to one user.

Add admin user create/disable/reactivate/password-reset controls and per-user logical
storage quotas/usage. Removing a track from one user must remove only their membership;
physical MP3 cleanup is allowed only after proving that no membership, playlist, share,
or protected history/reference requires it. Audit sensitive actions.

Update the web portal and Swift 5 SwiftUI iPhone/iPad/macOS client only as required for
the authenticated user's isolated library. Preserve manual Sync, offline-first playback,
Wi-Fi defaults, storage limits, low-energy behavior, and the public Cloudflare URL.

Build a two-user authorization matrix covering every affected endpoint plus duplicate
imports, quotas, disabled users, revoked devices, membership removal, export/deletion,
background jobs, backup, and isolated restore. Run proportional backend checks, full
tests/lint/type checks, migration drift, iOS build, and macOS build. Do not deploy until
the migration has been backed up and its production impact is reported. Write REPORT.md
with migrations, measured verification, deployment steps, rollback steps, and Sprint 15
readiness.
```
