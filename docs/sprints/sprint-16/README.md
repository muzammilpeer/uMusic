# Sprint 16 — Synchronized listening rooms

## Goal

Let two or more authorized users listen to a shared playlist at approximately the same
time on LAN or internet connections, with local pre-caching for fast, resilient playback.

## Dependencies

- Sprint 14 multi-user isolation is deployed and verified.
- Sprint 15 sharing permissions, invitations, and shared-playlist access are deployed.
- Participants can stream or download every track in the selected playlist.

## Product experience

- A user creates a private **Listening Room** from a shared playlist and becomes host.
- The host invites specific users or selects existing playlist members; there are no
  anonymous/public room links in this sprint.
- A readiness screen shows each participant as invited, joined, downloading, ready,
  reconnecting, or unavailable.
- Clients preflight and cache the current song plus configurable upcoming songs before
  enabling synchronized Start. Existing valid offline files are reused.
- The host can start, pause, resume, seek, skip, go back, and end the room. Participants
  initially follow host controls; optional co-host control can be granted explicitly.
- Late joiners cache the current track, seek to the authoritative position, and join at
  the next safe synchronization boundary.
- Each listener chooses their own output device and volume. No user's workout, location,
  HealthKit, listening history, or recommendation profile is shown to others.

## Synchronization architecture

- Add a Django ASGI realtime service using authenticated WebSockets and Redis-backed
  channel fan-out. Keep REST endpoints for create/join/leave/state/recovery operations.
- Store durable room membership, playlist revision, queue, current track, state revision,
  host/co-host roles, and lifecycle timestamps in PostgreSQL. Keep transient presence,
  acknowledgements, and frequent timing samples in Redis with bounded TTLs.
- Represent playback as versioned commands containing a monotonically increasing room
  revision, track ID, intended position, and a server timestamp scheduled slightly in
  the future. Ignore duplicated/out-of-order commands.
- Calibrate client/server clock offset and round-trip latency with repeated ping samples;
  use the lowest-latency samples rather than trusting device wall clocks directly.
- Start from a local cached MP3 at the scheduled monotonic deadline. Do not stream one
  audio byte stream to every client—the server coordinates state while each device plays
  its own authorized local/cache/HTTP media copy.
- Measure drift periodically at a battery-conscious rate. Ignore tiny drift, apply a
  short bounded rate correction for moderate drift, and seek only for large drift or
  track changes to avoid audible jumps.
- Suggested acceptance targets: median start skew no worse than 250 ms on a healthy LAN
  and 500 ms over a stable internet connection; document measured p95 results rather
  than claiming sample-accurate synchronization.

## Cache and network policy

- Reuse `OfflineManager.shared`, SHA-256 verification, user storage quota, Wi-Fi-only
  preference, and LRU rolling eviction.
- Reserve space before room preparation and show which participants cannot cache enough.
- Cache at least the current and next two tracks when policy/quota permits; make the
  look-ahead configurable without downloading an entire large playlist.
- Refresh expiring signed URLs before preflight. Revocation or loss of playlist access
  immediately blocks new fetches and room participation.
- LAN clients still authenticate through the backend. LAN discovery/MultipeerConnectivity
  may be evaluated later, but must not bypass permissions or create a second authority.
- If realtime connectivity drops, continue the already scheduled local track, attempt
  bounded reconnect, then reconcile to the newest room revision. Never spin network/CPU.

## Better-experience additions

- Add an optional per-device output-latency calibration offset for Bluetooth speakers or
  headphones; label it advanced because iOS cannot reliably discover every device's
  end-to-end acoustic delay.
- Show a compact room status in Now Playing: room name, host, participant count,
  connectivity, cache readiness, and sync quality—not precise location.
- Provide "Start when everyone is ready" and "Start anyway" controls to the host.
- Add a short countdown and haptic/visual cue before the first synchronized start.
- Allow reactions only as small ephemeral signals if desired later; do not add chat or a
  social feed in this sprint.
- Record per-device anonymous technical quality metrics (RTT, drift, correction count,
  buffer failures) for diagnostics, separate from listening/learning history.

## Apple client constraints

- Use `AVPlayer` local assets and monotonic scheduling; keep standard Now Playing and
  Lock Screen media metadata.
- iOS may suspend realtime sockets when the app is backgrounded. Design scheduled local
  playback to continue and reconcile on wake; do not promise continuous background
  WebSocket control without proving it on physical devices.
- Remote Lock Screen commands should affect the room only for host/co-host users and only
  when the app can deliver the command; otherwise keep them local or explain the limit.
- Preserve offline-first playback, manual library Sync, low-energy defaults, safe-area
  scrolling, and interactive keyboard behavior.

## Security, failure, and test matrix

- Host, co-host, participant, invited-but-not-joined, revoked, disabled, and unrelated
  user authorization for REST, WebSocket connect, room events, media, and recovery.
- Expired/replayed invitations, leaked room IDs, forged revisions, stale commands,
  duplicate delivery, reconnect storms, host disconnect, host transfer, playlist edits,
  deleted tracks, quota exhaustion, corrupt cache, signed URL expiry, and Redis restart.
- Simulated latency, jitter, packet loss, clock skew, out-of-order messages, offline/online
  transitions, late join, and mixed LAN/internet participants.
- Physical tests with iPhone/iPad/macOS, wired output, AirPods/Bluetooth, screen locked,
  app backgrounded, Low Power Mode, Wi-Fi-to-cellular transition, and Cloudflare path.
- Verify rooms never leak personal history, recommendations, fitness, location, device
  secrets, library items outside the shared playlist, or unrestricted user discovery.

## Out of scope

- Sample-accurate whole-home speaker synchronization comparable to dedicated audio
  hardware protocols.
- Anonymous/public rooms, cross-server federation, voice/chat/video, or shared workouts.
- Direct peer-to-peer media transfer that bypasses server authorization and auditing.
- Android, tvOS, watchOS, CarPlay, or smart-speaker clients.

## Exit criteria

- Two users complete create → invite → cache → ready → countdown → synchronized playback
  → pause/seek/skip → reconnect → end on LAN and internet test paths.
- Measured median and p95 start skew/drift are reported for each path and output type.
- Cached playback starts without fetching media again and survives a temporary realtime
  disconnect for the already scheduled track.
- Permission revocation blocks joining, control, and new media access.
- Realtime load, Redis restart recovery, battery/network use, and physical background/
  Lock Screen behavior have documented results and honest limitations.
- Backend tests/lint/type checks, migrations, readiness, Swift tests, iOS build, and macOS
  build pass; backup/restore and deployment rollback are exercised.

## Start

Use [PROMPT.md](PROMPT.md).
