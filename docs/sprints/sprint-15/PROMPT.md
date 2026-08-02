# Sprint 15 implementation prompt

```text
Implement Sprint 15 of uMusic only after Sprint 14 is deployed and its multi-user
isolation matrix passes. Read AGENTS.md and the uMusic development skill first.

Add private-by-default playlist sharing with owner, editor, and viewer roles. Implement
expiring single-use invitations for existing local users, accept/decline, member list,
role changes, revoke, leave, ownership transfer, and "Save to My Library" without
duplicating the underlying MP3. Avoid unrestricted user-directory enumeration.

Owners manage members and deletion. Editors may add/remove/reorder tracks but cannot
manage access. Viewers are read-only. Use database constraints and optimistic locking or
playlist revisions so concurrent edits cannot silently overwrite each other. Audit every
invitation and permission change.

Authorize playlist reads, mutations, streaming, signed downloads, playback sessions,
and offline sync through current membership. Revocation must block new online access
immediately. Define, implement, and surface a clear manual-sync policy for already cached
offline files. Sharing must never expose another user's listening history, learned taste,
recommendations, workout/HealthKit data, location, contexts, devices, imports, quota,
privacy export, or admin actions.

Add web and Swift 5 SwiftUI iPhone/iPad/macOS experiences for Shared with Me,
invitations, role badges, members, revoke/leave, collaborative editing, and saving music.
Keep controls scrollable above the mini player and keyboard, preserve offline-first
playback/manual library Sync, and require confirmation for destructive actions.

Test owner/editor/viewer/unrelated users, invitation expiry/replay/enumeration, disabled
users, revoked devices, concurrent edits, playlist deletion, access revocation, signed
URL bounds, offline reconciliation, deduplicated media, and final-reference cleanup. Run
the complete backend and Apple validation matrix. Write REPORT.md with schema/API changes,
permission table, offline-revocation policy, measured results, deployment/rollback steps,
and remaining limitations. Do not add public links, federation, chat, or social features.
```
