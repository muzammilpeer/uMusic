# Threat and Privacy Model

## Protected assets

- Server credentials, access/refresh tokens, authenticated media tickets.
- Listening timelines, learned taste, playlist intent, explicit likes/dislikes.
- Activity, workout, coarse place, route category, and calendar preferences.
- Cached audio/artwork and full research exports.
- Model integrity, catalog integrity, and queue/restoration state.

## Trust boundaries

1. SwiftUI app ↔ `UMusicCore.xcframework` public API.
2. Framework ↔ Keychain/Core Data/media files.
3. Client ↔ private Django API over TLS.
4. Containing app ↔ share extension via App Group/shared Keychain.
5. App ↔ system share sheet/export destination.
6. Signed/bundled model ↔ recommendation runtime.

## Principal threats and controls

| Threat | Example | Required controls | Verification |
|---|---|---|---|
| Secret disclosure | token in URL/error/export | Keychain only, header auth, redacted structured logging, export denylist | fixture/log/export scans |
| Cross-user residue | logout then another user sees cache/history | namespace stores/files by installation+account; explicit logout cleanup options | account-switch tests |
| Tampered sync/media | corrupt metadata or MP3 | TLS, revisions, schema validation, checksums, atomic commit | contract/integrity tests |
| Malicious shared URL | oversized/unsupported/custom scheme | HTTP(S) allowlist, size limits, normalization, server validation, idempotency | extension fuzz fixtures |
| Sensitive overcollection | continuous location/workout history | independent opt-in, session scope, coarse derivation, short raw lifetime, no default upload | permission/store audit |
| Inference of religion | forced religious queue | user-selected preference only, instant override, no identity inference | policy tests |
| Export leakage | full history sent unintentionally | sanitized default, content preview, protected temp file, cleanup, optional encryption | export integration tests |
| Model tampering | substituted ranker | bundled trust/signature, schema check, canary, rollback, heuristic fallback | corrupt-model tests |
| Denial of playback | ranker/server/sensor failure | cached playback, bounded timeouts, deterministic fallback, unknown context | chaos tests |
| Path traversal | server filename controls local path | content-addressed internal names; never trust remote filenames | malicious fixture tests |
| Database corruption | crash during sync/reducer | WAL, atomic pages/checkpoints, migrations, staging swap, backups | interruption tests |
| Excess background use | sensors/downloads continue | lifecycle ownership, cancellation, OS background APIs, energy policy | background/energy tests |

## Privacy defaults

- Basic playback requires no Motion, HealthKit, or Location permission.
- Low Energy Mode is on.
- Offline downloads are unmetered-network only.
- Raw events retain 90 days; users may shorten or delete them.
- Precise location and raw workout samples are not part of the recommendation event schema.
- Personal learning stays on device and has no default API upload endpoint.
- Auto-grow playlists and Ramadan preference are off until explicitly enabled.

## Abuse and failure cases

- Denied/revoked permissions resolve to `unknown`; playback and sync continue.
- Compromised server responses cannot instruct the app to run code, open arbitrary schemes, or write arbitrary paths.
- A playlist share/mirror may include final membership but never context, location, health, or learned reasons.
- Diagnostic support packages are sanitized by construction, not by user memory.
- Logout does not silently destroy local data; destructive cleanup is separately confirmed and scoped.

## Review checkpoints

Re-run threat review when adding a persisted field, permission, App Group capability, export destination, downloaded model, personal sync, sharing, or new server endpoint.

