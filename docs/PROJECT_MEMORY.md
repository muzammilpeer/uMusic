# uMusic project memory

This repository contains a private, self-hosted adaptive music system:

- Django 5.2 backend with PostgreSQL, Redis/Celery, Docker, and pluggable media storage.
- Swift 5 SwiftUI client targeting iPhone, iPad, and macOS.
- Production URL: `https://umusic.muzammilpeer.uk/` through Cloudflare Zero Trust.
- MP3-only direct upload and remote MP3/YouTube import with ID3 metadata.
- The iOS and macOS apps include a compact `Import to uMusic` Share Extension. It previews the
  YouTube URL and queues it with one **Download** tap; the main app must have been opened
  and signed in at least once.
- Activity-aware playback for cycling, running, walking, gym, focus, and relaxation.

## Current client behavior

- Library metadata is cached locally and never auto-synced at launch.
- The user presses the top-right **Sync** button to refresh songs and playlists.
- Search operates against the locally cached library.
- Playback prefers downloaded MP3 files before requesting a server stream.
- The player and download UI share one `OfflineManager`; do not create independent
  default cache managers or newly downloaded files will appear missing until relaunch.
- The last song, queue, seek position, and offline state survive app relaunch.
- The bottom Resume player appears immediately from local state.
- The mini player is attached to the active detail view's safe-area inset so the final
  list/form row remains scrollable above it.
- All text-entry screens use interactive keyboard dismissal. Keep login, import,
  workout, search, and other forms scrollable while the keyboard is visible.
- Offline storage has a hard user-selected quota beginning at 100 MB.
- Downloads default to Wi-Fi-only; least-recently-used rolling files are evicted first.
- Songs can be removed from a playlist, from device storage, or—after administrator confirmation—from the server.
- Listening events are stored locally and uploaded in batches.
- Offline session duration is user-selectable. Recommendation energy is currently an
  internal balanced default (`0.75`); do not restore an unexplained slider.

## Current backend/API behavior

- Device authentication is authoritative: a device token resolves its owning user.
- UUID URL path handling accepts the uppercase UUID strings emitted by Foundation, and
  the Swift client lowercases UUID path segments. Collection request bodies are also
  normalized before dictionary lookup.
- Playback-session and queue endpoints return a controlled `400` for malformed or
  missing track IDs rather than raising `KeyError`/HTTP 500.
- Signed playback/download links are intended to remain usable for one week unless
  revoked by authorization or policy.
- Production source is baked into Docker images. Backend edits require rebuilding and
  recreating only affected services; never remove the PostgreSQL, media, Redis,
  quarantine, or backup volumes.
- Readiness is `/health/ready/`. Public traffic uses
  `https://umusic.muzammilpeer.uk/` through Cloudflare Zero Trust.

## Recent resolved failure patterns

- A `404` on UUID endpoints can be caused by uppercase Foundation `UUID.uuidString` in
  a case-sensitive Django route. Lowercase client path segments and retain the backend
  case-insensitive UUID converter.
- Full Resync once downloaded files successfully and then returned HTTP 500 while
  creating its playback session. The cause was uppercase UUID dictionary lookup; keep
  request UUID normalization and its regression coverage.
- `URLSession` async `download(for:)` cannot be used with a background configuration
  that expects completion handlers. The current foreground, connectivity-aware session
  is deliberate; a true background downloader needs a delegate and restoration flow.
- Slow home-screen playback after downloading was caused by two in-memory offline cache
  indexes. Keep `OfflineManager.shared` as the default for the player and Offline UI.
- The Share Extension and containing Apple app share the device token through the
  `3S2DR3CGY4.app.umusic.shared` keychain access group. Preserve legacy-token migration
  on both iOS and macOS.
- macOS matches the shared library, offline, player, imports, location, activity-session,
  quota, charging-policy, and admin flows. HealthKit and Core Motion classification are
  honestly replaced by manual Mac session behavior rather than inactive controls.
- macOS download policy treats Wi-Fi and wired Ethernet as unmetered. The Offline screen
  exposes connection state, blocks preparation only for a real policy/availability
  reason, and reports activity/device errors instead of silently returning.
- Offline Download, Full Resync, and per-track sync controls remain clickable unless the
  same operation is running; a tap reports the exact network, charging, activity, or
  device-registration blocker rather than presenting an unexplained disabled button.
- Listening fact rebuilds lock the owning user so concurrent Mac/iPhone event batches do
  not race into the `unique_owner_playback_fact` constraint.

## Workout and energy behavior

- The main **Start Workout Session** button is at the top of the Workout screen.
- uMusic Low Energy Mode is enabled by default.
- Motion detection runs only when requested and samples for up to five seconds in low-energy mode.
- Indoor activities do not use GPS.
- Without route opt-in, outdoor workouts request one coarse location and stop GPS.
- Raw route recording is explicit and uses coarse, distance-filtered updates.
- HealthKit workout data is event-driven and stops when the session finishes.

## Apple platform limitations

- Apps cannot enable the iPhone's system Low Power Mode.
- Public iOS APIs do not expose AirPods or generic Bluetooth-headset battery percentages.
- Standard Lock Screen media controls cannot contain arbitrary workout statistics; that requires a future ActivityKit Widget/Live Activity extension.

## Planned multi-user work (not implemented)

- [Sprint 14](sprints/sprint-14/README.md) introduces private per-user library
  memberships while retaining deduplicated global MP3/catalog objects, strict tenant
  isolation, quotas, migration/backfill, and two-user authorization tests.
- [Sprint 15](sprints/sprint-15/README.md) adds private-by-default playlist sharing,
  owner/editor/viewer roles, expiring invitations, revocation, collaborative updates,
  and web/SwiftUI workflows.
- [Sprint 16](sprints/sprint-16/README.md) adds private synchronized Listening Rooms
  over LAN or internet using authenticated realtime coordination, local pre-caching,
  clock calibration, drift correction, readiness, and reconnect recovery.
- Until Sprint 14 is completed and deployed, do not describe the current library as
  safely multi-tenant. Playlist sharing must not begin before its isolation gate passes.
- Listening Rooms must not begin before Sprints 14 and 15 pass. They coordinate each
  device's local playback; they do not stream one shared audio byte stream or promise
  sample-accurate synchronization.

## Development entry point

Future Codex sessions must start with [AGENTS.md](../AGENTS.md), then follow the repository-local skill at:

`../.codex/skills/umusic-development/SKILL.md`

That skill routes Apple, backend/deployment, and product work to separate short references to minimize token usage.

## Essential validation

```sh
swift test --package-path clients/UMusic
xcodebuild -quiet -project clients/UMusic/UMusic.xcodeproj -scheme UMusic -destination 'generic/platform=iOS' -derivedDataPath /tmp/umusic-ios CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project clients/UMusic/UMusic.xcodeproj -scheme UMusic -destination 'generic/platform=macOS' -derivedDataPath /tmp/umusic-macos CODE_SIGNING_ALLOWED=NO build
docker compose exec -T web python manage.py check
curl -fsS http://127.0.0.1:8000/health/ready/
```

Never store credentials in documentation or source, remove Docker volumes during ordinary deployments, or claim access to unavailable Apple APIs.
