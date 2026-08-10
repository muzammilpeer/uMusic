# Sprint 6 Report

Status: **Offline engine implemented and locally validated; signed-device background transfer testing remains**  
Date: 2026-08-09

## Delivered behavior

- One shared `DownloadCoordinator` implements both `OfflineManaging` and playback’s `CachedMediaLocating` seam. The live player and Offline Storage UI receive the same actor instance.
- Delegate-based background `URLSessionDownloadTask` transport with stable iOS/macOS session identifiers; it does not use completion-handler `download(for:)` with a background configuration.
- Reattachment to existing background sessions and an async recovered-completion stream.
- iOS app-delegate background-session completion registry calls the system completion handler only after delegate events finish.
- Download callback files are moved immediately into stable staging storage before asynchronous verification.
- Streaming SHA-256 and exact-size verification before an atomic partial-to-final MP3 commit.
- Versioned atomic cache index containing stable track ID, safe display metadata, relative path, checksum, byte count, pinned/rolling retention, access time, and predicted-utility seam.
- Hard configurable quota with 100 MB, 500 MB, 1 GB, and custom-MB UI.
- Rolling eviction orders low predicted utility first and least-recent access second.
- Pinned and currently playing media are never eviction candidates and cannot be manually removed while playing.
- Wi-Fi/unmetered-only behavior by default. Enabling cellular is an explicit persisted setting. On macOS, Ethernet remains allowed because only cellular access is restricted.
- Duplicate concurrent requests share one transfer; a concurrent pin request upgrades the final entry to pinned.
- Explicit reconciliation removes orphaned media files, drops missing index entries, and reapplies quota.
- Library track menu supports Download, Download and Keep, and Remove Download.
- Offline Storage UI shows usage, quota, network policy, downloaded entries, retention state, sizes, and removal.
- Playback checks the shared cache on every track preparation before requesting a streaming ticket.
- Framework version advanced to `2.0.0-alpha.6`; public API baselines were refreshed and verified.

## Validation

- 46 Swift tests pass.
- Offline coverage includes atomic verified commit, relaunch, duplicate requests, checksum corruption, partial files, expired tickets, airplane mode, disk-full errors, rolling eviction, pinned/current-track protection, quota reduction, orphan reconciliation, restored delegate completion, and cellular-policy persistence.
- Generic iOS and macOS builds pass with code signing disabled.
- Public production symbol-graph baselines pass. SwiftPM continues to print its known test-bundle graph warning after successfully emitting the production graphs.

## Boundaries and remaining gates

- Background session restoration and completion wiring compile and pass injected delegate-completion tests, but must still be exercised in a signed app through suspension, termination, relaunch, and device reboot.
- Predicted utility is currently neutral (`0`) until the recommendation/learning sprint supplies scores; eviction therefore falls back to LRU.
- The UI exposes configured network policy, not a claim about the device’s live interface or charging state. No charging-only policy has been added.
- Download progress percentages are not yet persisted or streamed to SwiftUI; the UI reports aggregate active task count when refreshed.
- Cache lookup validates recorded size and existence. Full SHA-256 is performed at commit; periodic full-file integrity audits remain a future maintenance operation.
- A failed download may occur after rolling files were evicted to reserve hard-quota capacity. Pinned/current media remain protected.
- Logout-specific offline deletion still requires the unified local-data clearing coordinator.
- No backend changes or Docker deployment were required; Sprint 4 playback tickets already provide byte-range-capable signed media URLs.

## Next sprint entry

Sprint 7 should complete Songs, Albums, Artists, Genres, Era, Downloaded, Playlists, cached search/filtering, track menus, deep links, and accessibility while preserving queue and offline state.
