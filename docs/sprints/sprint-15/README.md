# Sprint 15 — Playlist sharing and collaboration

## Goal

Let users deliberately share playlists and server-available music while keeping all
personal history, fitness, location, contexts, and recommendation profiles private.

## Dependencies

- Sprint 14 is complete, deployed, backed up, and its two-user isolation matrix passes.

## Sharing model

- Playlists are private by default.
- Roles are `owner`, `editor`, and `viewer`.
- Owners can invite, change roles, revoke access, transfer ownership, or stop sharing.
- Editors can add, remove, and reorder tracks but cannot manage members or delete the
  playlist. Viewers cannot mutate it.
- Invitations target an existing local username/email and use expiring, single-use
  tokens. Do not expose the server's user directory through unrestricted search.
- Saving a shared track to "My Library" creates the recipient's membership without
  copying the physical MP3.
- Leaving or losing access removes the shared playlist from the recipient but never
  removes their independently saved library membership or offline file automatically.

## Deliverables

- Playlist membership/invitation models with database constraints and audited state
  transitions.
- APIs for share, accept/decline, list members, change role, revoke, leave, and copy/save.
- Permission-aware playlist read/update/delete and track stream/download authorization.
- Conflict-safe collaborative reorder/update using a revision or optimistic-lock token.
- Web portal screens for "Shared with me", invitations, members, roles, revoke, leave,
  and save to library.
- SwiftUI iPhone/iPad/macOS screens for the same essential workflows, including clear
  ownership/role badges and confirmation for destructive actions.
- Offline behavior: explicitly downloaded shared songs continue only while authorized;
  on the next manual sync, revoked content becomes unavailable and its local copy is
  removed after confirmation or according to a documented secure policy.
- Notifications remain in-app; email and push notifications are optional and off by
  default for the self-hosted product.

## Security and test matrix

- Owner/editor/viewer/unrelated-user tests for every operation.
- Invitation replay, expiration, guessing, enumeration, revoked user/device, disabled
  account, concurrent reorder, deleted playlist, and deleted membership cases.
- Verify shared access never leaks another user's history, recommendation reasons,
  contexts, fitness, location, devices, quotas, imports, or admin capabilities.
- Verify signed URLs cannot outlive authorization beyond their bounded expiry and are
  rejected or made short-lived for revoked shares.

## Out of scope

- Public or anonymous share links.
- Cross-server/federated sharing.
- Social feed, messaging, comments, reactions, followers, or public user discovery.
- Shared recommendation/fitness profiles.

## Exit criteria

- A three-user owner/editor/viewer journey passes on web and Apple clients.
- Private-by-default and least-privilege behavior is proven by automated tests.
- Concurrent playlist updates do not silently overwrite another user's changes.
- Revocation blocks new streaming/download immediately and has documented offline rules.
- Physical MP3 deduplication and reference-safe deletion remain correct.
- Django tests, security matrix, Ruff, mypy, readiness, iOS build, and macOS build pass.

## Start

Use [PROMPT.md](PROMPT.md).
