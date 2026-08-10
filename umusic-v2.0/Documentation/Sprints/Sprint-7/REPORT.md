# Sprint 7 Report

Status: **Cached library navigation, local playlists, search, actions, and deep links implemented and locally validated**  
Date: 2026-08-09

## Delivered behavior

- Complete cached Library sections for Songs, Albums, Artists, Genres, Era, Downloaded, and Playlists.
- Album, artist, genre, language, and year metadata now survive the Core Data-to-domain projection used by browsing, queue snapshots, and playlist items.
- Unknown Album, Unknown Artist, Unknown Genre, Unknown Year, and unknown language remain visible and filterable instead of being discarded.
- Composable cached filters for artist, album, genre, language, year, and free text.
- Debounced 250 ms local search in both Library and Search tabs. Search remains a background Core Data query and never initiates server sync.
- Page-batched Core Data identity resolution replaces per-track fetches during catalog apply.
- Track action menus for Play Now, Play Next, Add to Queue, Download, Download and Keep, Remove Download, and Add to Playlist.
- Queue actions preserve the current navigation and search state.
- Downloaded browsing uses the same shared offline index used by playback and Offline Storage.
- Atomic local manual-playlist storage with create, rename, delete, add, remove, duplicate-track support, and monotonic optimistic revisions.
- Stale playlist mutations are rejected; UI reload/retry behavior avoids silently overwriting newer state.
- Playlist removal mutates only the playlist JSON document. It has no dependency on catalog, backend media, or offline-file deletion.
- `umusic://track/{uuid}`, `umusic://playlist/{uuid}`, and `umusic://search?q=...` deep links route into the existing independent tab stacks.
- Semantic fonts, explicit VoiceOver labels, contained accessibility elements, keyboard-capable native controls, and interactive keyboard dismissal.
- Mini-player safe-area behavior from Sprint 4 remains attached above all Library/Search content.
- Framework version advanced to `2.0.0-alpha.7`; public API baselines were refreshed and verified.

## Validation

- 53 Swift tests pass.
- A 25,000-track paged import plus targeted cached search passes; the measured search portion completed in approximately 0.29 seconds on the local development environment, below the two-second test budget.
- Coverage includes duplicate titles, unknown metadata, composable filters, playlist CRUD/relaunch, duplicate playlist tracks, optimistic conflicts, invalid names/indexes, deep links, accessibility-source contract, cached/offline behavior, and all prior sprint tests.
- Generic iOS and macOS builds pass with code signing disabled.
- Public production symbol-graph baselines pass. SwiftPM still prints its known test-bundle graph warning after emitting the required production graphs.

## Boundaries and remaining gates

- Manual playlists are local device state in this sprint. They are not uploaded or reconciled with Django; optimistic revisions protect local concurrent/stale UI operations. A future server-mirroring design must define identity, ownership, and conflict behavior before enabling upload.
- Album and artist grouping currently uses normalized display strings because the Sprint 3 local projection does not yet preserve their server UUIDs.
- Track and playlist deep links use stable UUIDs. Facet navigation is local in-screen state and is not yet encoded as a shareable URL.
- Playlist track reordering is not yet exposed; create, rename, delete, add, and remove are implemented.
- Search includes songs and track metadata. Playlist-name search remains within the Playlists section rather than being merged into song results.
- VoiceOver order and Dynamic Type use semantic SwiftUI controls and source-contract tests, but physical accessibility testing across the largest text sizes remains a release gate.
- No backend changes or Docker deployment were required.

## Next sprint entry

Sprint 8 should implement the Start Listening hero, explicit Resume card, last-ten-calendar-day grouped history, starter mixes, complete loading/offline/error polish, and persisted system/light/dark theming without enabling recommendation learning early.
