# Sprint 16 implementation prompt

```text
Implement Sprint 16 of uMusic only after Sprints 14 and 15 are deployed and their
multi-user isolation/sharing security matrices pass. Read AGENTS.md and the repository
uMusic development skill first. Preserve production data, manual library Sync,
offline-first playback, quotas, Wi-Fi defaults, and low-energy behavior.

Build private synchronized Listening Rooms for authorized members of a shared playlist.
The creator is host; allow explicit co-hosts. Host/co-host may start, pause, resume, seek,
skip, go back, or end. Regular participants follow. Add REST APIs for durable room
lifecycle/recovery and authenticated Django ASGI WebSockets with Redis fan-out for
realtime state. Persist authoritative room membership, playlist/queue revision, current
track, playback revision, and lifecycle in PostgreSQL; keep transient presence/timing in
Redis with bounded TTLs. Never use room IDs alone as authorization.

Model each playback change as an idempotent, monotonically versioned command containing
track ID, intended position, and a server timestamp scheduled in the future. Estimate
client/server clock offset and RTT using multiple ping samples and monotonic clocks.
Ignore duplicate/stale/out-of-order commands. Start each client's own authorized cached
MP3 at the scheduled deadline. Use conservative drift handling: tolerate tiny errors,
brief bounded playback-rate correction for moderate drift, and seek only for large drift.
Measure and report actual median/p95 skew; do not claim sample-accurate synchronization.

Before Start, add a readiness lobby that preflights permissions, storage, checksum, and
current plus next tracks using OfflineManager.shared. Reuse cached files, respect each
user's quota/cellular policy, refresh signed URLs, show per-user ready/downloading/error
states, and provide host controls for Start When Everyone Is Ready or Start Anyway. Add
a countdown, late join, bounded reconnect/backoff, newest-revision reconciliation, host
disconnect/transfer policy, and Redis restart recovery. During a network gap, continue
only already scheduled local playback; avoid CPU/network polling loops.

Add Swift 5 SwiftUI iPhone/iPad/macOS room creation, invitations, lobby, participant
status, cache progress, host controls, compact Now Playing room status, sync-quality
diagnostics, and an optional advanced per-device output-latency offset for Bluetooth.
Volume/output remain personal. Preserve standard Lock Screen controls and explicitly
handle iOS background WebSocket suspension: scheduled audio continues locally and state
reconciles on wake. Do not promise background realtime controls until physical tests
prove them.

Keep workout, HealthKit, location, listening history, learned taste, recommendations,
device secrets, and non-shared library data private. Do not add public links, chat,
federation, shared workouts, or peer-to-peer media that bypasses backend authorization.

Test the complete permission matrix plus invitation replay, forged revisions, duplicate/
out-of-order events, latency/jitter/loss/clock skew, late join, reconnect storms, host
loss, playlist edits, revoked access, corrupt/missing cache, quota failure, signed URL
expiry, Redis restart, LAN, internet, Cloudflare, locked screen, backgrounding, Low Power
Mode, wired output, and Bluetooth/AirPods. Add deterministic timing simulations and
physical two-device tests. Run backend tests/lint/type checks/migration checks/readiness,
Swift tests, iOS and macOS builds, backup/restore, and rollback rehearsal. Write REPORT.md
with protocol/schema, state machine, permission table, cache policy, measured median/p95
sync results, battery/network measurements, deployment steps, rollback, and limitations.
```
