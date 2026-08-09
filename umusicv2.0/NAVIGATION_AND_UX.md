# Navigation and UX Specification

## App shell

Use four primary tabs: **Home**, **Library**, **Now**, and **Search**. A global mini player sits above the tab bar whenever a playable snapshot exists. On iPad/macOS the same destinations may use a sidebar, but route identities remain stable.

```text
Root
├── Setup / Authentication
└── Main Shell
    ├── Home
    ├── Library
    │   ├── Songs
    │   ├── Albums
    │   ├── Artists
    │   ├── Genres
    │   ├── Downloaded
    │   └── Playlists
    │       └── Playlist Detail / Auto-grow Rules
    ├── Now / Now Playing
    │   ├── Queue
    │   ├── Activity & Context
    │   └── Visualizer
    ├── Search
    └── Settings (toolbar/avatar route from Home and Library)
```

## First run

1. Welcome: explain private server and local personalization in plain language.
2. Connect: server URL, username, password, Keep Me Signed In.
3. Validate connection and show library count/storage estimate.
4. Choose offline quota and network policy; defaults can be accepted.
5. Optional taste seed: languages, genres, eras, and a Ramadan preference. Skip is prominent.
6. Permissions are requested only at the feature moment, never as a startup wall.
7. Sync metadata, then show Home. Start Listening works as soon as a minimum playable page exists.

## Home

- Hero: **Start Listening**; secondary line explains current starting context, e.g. “A varied mix for Sunday morning.”
- Resume card when a prior snapshot exists: track, position, and Resume button.
- Recent contexts: last 10 calendar days grouped by date, then activity/context. Each group shows tracks, total listening time, and a Play This Mix action.
- For You: lightweight rows for activity, time, genre, language, and era mixes. Hide until enough confidence exists.
- Downloads/status card only when action is needed.
- Empty state never looks broken: show starter genres/eras and recently added music.

## Library

- Segmented/top destinations for Songs, Albums, Artists, Genres, Downloaded, and Playlists.
- Cached data appears immediately. Sync is a deliberate toolbar action with progress and last-sync time.
- Track menu: Play Now, Play Next, Play Later, Add to Playlist, Download, Favorite, Dislike, View Details.
- Playlist detail: Play, Shuffle, Download, edit/reorder, auto-grow toggle, rules summary, additions history, undo.
- Era browsing uses release decade and exact year filters without assuming a missing year.

## Now

This tab presents the full player; tapping/swiping the mini player reaches the same route.

- Artwork, title, artist, album, scrubber/time, play/pause, previous/next, ±15 seconds.
- Route picker and platform-appropriate volume control.
- Expandable queue with manual entries visually distinguished and protected from automatic refill/reorder.
- Activity chip: Manual/Detected/Unknown, tap to change.
- “Why this track?” sheet with compact, non-sensitive reason codes.
- Favorite/dislike and optional notes; dislike confirmation is undoable.
- Optional visualizer panel; respect Reduce Motion and Low Energy Mode.
- Swipe down dismisses presentation but playback continues.

## Search

- Debounced local search over cached tracks, albums, artists, genres, languages, years, and playlists.
- Filters are composable and survive navigation during the session.
- Results support all queue actions without leaving search.
- Server search is an explicit fallback if the local catalog is incomplete, never a hidden launch sync.

## Global mini player

- Visible on all primary screens when a snapshot exists.
- Artwork, title, artist, play/pause, next; accessibility labels include playback state.
- Safe-area inset prevents content and keyboard controls from being obscured.
- Gestures supplement, never replace, buttons.

## Settings map

- Account: server, connection status, keep-signed-in, logout.
- Playback: crossfade/gapless only if engine supports them reliably, explicit content, queue behavior.
- Offline Storage: quota, used/pinned/rolling space, Wi-Fi/unmetered policy, cleanup.
- Personalization: learning on/off, exploration level, Ramadan preference, smart-playlist defaults, reset learning.
- Activity & Sensors: manual default, Motion, HealthKit, Location, route-category collection, Low Energy Mode.
- Privacy & Retention: raw-event duration, coordinate policy, delete history, export preview.
- Appearance: system/light/dark, accent, visualizer, Reduce Motion linkage.
- Export & Diagnostics: sanitized export, full export, logs, database schema/version.

## Navigation implementation rules

- Typed `AppRoute`, `SheetRoute`, and `PlayerRoute`; views never push arbitrary strings.
- One `NavigationStack` per tab preserves independent history.
- Deep links cover track, album, artist, playlist, import job, settings subsection, and Now Playing.
- Playback state is independent of view lifecycle.
- Loading, empty, offline, permission-denied, recoverable-error, and fatal-configuration states are designed for every screen.

