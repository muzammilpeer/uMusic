# Sprint 15 progress report

- Status: implementation complete; deployment acceptance pending
- Started: 2026-08-03
- Deployment: not deployed

## Foundation implemented

- Added playlist revision numbers for optimistic concurrency control.
- Added unique per-playlist user access grants with editor/viewer roles and
  active/revoked/left lifecycle states.
- Added targeted invitation records with hashed secrets, random prefixes, expiry,
  single-use response state, and no public user-directory requirement.

## Implemented

- Added private-by-default owner/editor/viewer authorization, audited targeted
  invitations, accept/decline, role changes, revoke, leave, ownership transfer, and
  save-to-library endpoints.
- Added optimistic playlist revisions; stale collaborative changes return HTTP 409.
- Shared tracks can be resolved and streamed only while access is active. Saving adds a
  private membership without copying the MP3; signed fetches re-check authorization.
- Added web portal pages for shared playlists, invitations, member invitation/revoke,
  leave, and save-to-library.
- Added SwiftUI role labels, shared-track playback, save, leave, and invitation
  accept/decline workflows shared by iPhone, iPad, and macOS.
- Added a focused owner/editor/viewer/unrelated security suite. The 15 relevant playlist,
  library, playback, and sync tests pass.
- Generic iOS and macOS Xcode builds pass with code signing disabled.

## Verification and deployment gate

- The final all-project Docker test/lint/mypy command could not run because the Codex
  environment reached its Docker approval/usage limit. The last focused run reached 15
  passing tests; its lint pass was interrupted by formatting findings that were then
  corrected.
- All 5 Swift package tests pass using an isolated module cache with the SwiftPM sandbox
  disabled; both Xcode product builds also pass.
- Sprint 15 is not deployed. Run the complete regression suite, migration drift check,
  backup/restore drill, production migration, readiness check, and physical three-user
  acceptance before deployment or starting Sprint 16 implementation.
