# Sprint 5 Report

Status: **Durable queue and paused restoration implemented and locally validated**  
Date: 2026-08-09

## Delivered behavior

- Schema-versioned `DurableQueueSnapshot` containing stable queue-item identities, safe track snapshots, manual/automatic origin, current index, seek position, cached/remote source identity, and save time.
- Atomic protected JSON persistence in Application Support through `FileQueueSnapshotStore`.
- Synchronous snapshot loading during composition so the previous track and mini player are visible immediately.
- Restored media attaches asynchronously, prefers a currently available cached file, otherwise requests a fresh remote ticket, seeks to the saved position, and remains paused.
- A Play command received while restored media is still preparing is retained and starts only after preparation and seek complete.
- Meaningful transition persistence for queue changes, track changes, play/pause, seek, route loss, completion, and scene inactivity/background.
- Position checkpoints occur only after crossing a 15-second boundary; playback ticks are not stored as telemetry.
- Stable queue-item UUIDs preserve duplicate songs as distinct entries.
- Manual Play Next inserts immediately after the current item. Manual Play Later remains ahead of automatic refill items. Priority is normalized after reordering.
- Identity-based queue removal and reordering, including duplicate tracks.
- Queue exhaustion leaves the final track visible and paused.
- Now screen queue UI displays the current item and origin and provides move/remove actions.
- Framework version advanced to `2.0.0-alpha.5`; public API baselines were refreshed and verified.

## Validation

- 37 Swift tests pass.
- Sprint 5 coverage includes immediate force-quit-style restoration, no autoplay, seek restoration, Play-during-prepare intent, manual priority, duplicates, corrupt state, queue exhaustion, identity-based remove/reorder, cache fallback, and checkpoint write budget.
- Generic iOS and macOS builds pass with code signing disabled.
- Public symbol-graph baseline check passes for `UMusicCore`, `UMusicDomain`, and `UMusicImportClient`. SwiftPM still emits its known test-bundle symbol-graph warning after successfully generating the production graphs.

## Boundaries and remaining gates

- Automatic refill is represented by queue-item origin and ordering rules only. Recommendation generation remains Sprint 11.
- Offline cache implementation remains Sprint 6. Restoration currently uses the shared cache protocol with the live empty placeholder, then falls back to a fresh remote ticket.
- Track snapshots do not yet carry catalog revision/checksum fields, so stale server revision reconciliation is limited to ticket availability. Sprint 6 catalog/media identity integration must close this before release.
- The queue file is local device state and is not uploaded to the backend.
- Logout-specific queue deletion is not yet connected to `removeAllDeviceData`; it should be wired when the unified local-data clearing coordinator is implemented.
- Signed-device force-quit, background suspension, Bluetooth, and route-change tests remain physical release gates.
- No backend changes or Docker deployment were required for Sprint 5.

## Next sprint entry

Sprint 6 should replace `EmptyMediaCache` with one shared offline cache index and download coordinator, add checksum/size verification, quota enforcement, pinned versus rolling state, background task restoration, and cache reconciliation.
