# Sprint 3 Report

Status: **Core catalog sync implemented and locally validated; large-scale/staging-store hardening remains**  
Date: 2026-08-09

## Delivered behavior

- Authenticated `GET /api/v2/library/changes` backend endpoint with signed opaque cursors, fixed snapshot pagination, a maximum 500-row page, per-user isolation, active-track changes, and removal tombstones.
- Steady cursors establish a fresh upper boundary only when the next explicit sync begins; multi-page requests retain one immutable boundary.
- Rich catalog payloads containing stable IDs, monotonic revisions, artist/album/genre/year/duration, analysis placeholders, artwork/audio identity, and availability.
- Swift wire DTO decoding and an authenticated URLSession catalog client.
- Versioned `UMusicCatalogV1` Core Data store using automatic lightweight migration, uniqueness constraints, search indexes, and background contexts.
- Atomic persistence of each page and its next cursor, revision guards against stale/out-of-order pages, validation before writes, and tombstones that hide unavailable tracks while retaining safe metadata.
- Cached catalog snapshot at startup; authentication does not trigger sync.
- Actor-owned explicit sync loop with cancellation checks and cached-data preservation on network failure.
- Library screen with a deliberate Sync action, progress state, cached track list, and non-destructive error messaging.
- Framework version advanced to `2.0.0-alpha.3`.

## Validation

- 25 Swift tests pass, including atomic cursor commits, duplicate/out-of-order revision protection, tombstones, local search, invalid-page rollback, authentication, architecture boundaries, and prior sprint coverage.
- Generic iOS and macOS app builds pass with code signing disabled.
- 15 affected Django account/library tests pass.
- Ruff, Django system checks, and MyPy pass for affected backend code.

## Intentional boundaries and remaining hardening

- Sync remains user initiated. No launch, background, periodic, or post-login auto-sync exists.
- Playback, media download, playlists, and learning are not part of this sprint.
- The current v1 store keeps track-facing artist/album/genre values on the catalog row. A later schema revision must normalize these into dedicated entities before relationship-heavy browsing ships.
- Production-scale 25,000-track profiling, interrupted full-resync staging-store swap, checksum enforcement for locally downloaded media, and a live signed-device/server pass remain release gates.
- The backend currently returns nullable language and analysis placeholders where legacy metadata has no validated value; future ingestion should populate them without breaking the v2 envelope.

## Next sprint entry

Sprint 4 can begin with playback state restoration and the persistent mini-player, consuming only locally cached catalog records and leaving recommendation learning disabled until its planned sprint.
