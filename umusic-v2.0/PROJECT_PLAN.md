# uMusic 2.0 Product and Requirements Plan

## 1. Vision

uMusic builds a private taste model from listening behavior and current context, then turns **Start Listening** into a dependable, low-friction personal radio. The experience begins with safe library heuristics and becomes more personal as the device learns.

## 2. Success criteria

- A configured user can begin playback in two taps or fewer from app launch.
- A first-time user receives a valid, varied queue without any behavioral history.
- A returning user sees the previous track and position immediately and can resume intentionally.
- Cached music plays without a network connection.
- No context permission is required for basic playback.
- Recommendation generation stays below 150 ms at p95 on the minimum supported device for a 25,000-track library, excluding media preparation.
- Routine telemetry produces no more than one durable write every 30 seconds and one aggregate flush every 120 seconds in Low Energy Mode.
- The app remains responsive while syncing, indexing, downloading, exporting, or running inference.
- Users can inspect, export, shorten retention, reset learning, and disable each sensitive signal.

## 3. Personas and core journeys

### Private-server listener

Configures server URL and credentials, syncs a large collection, chooses an offline quota, and presses Start Listening.

### Activity listener

Manually selects or optionally detects walking, running, cycling, gym, focus, relaxation, commuting, driving, sleep preparation, or an extensible custom activity. The selection affects ranking but never prevents playback.

### Intentional curator

Searches the library, creates playlists, adds a track to Up Next, reorders the queue, and chooses whether a playlist may grow automatically.

### Developer/researcher

Exports sanitized or full local learning data, opens the inspectable store on macOS, evaluates models, and imports a signed model update.

## 4. Functional requirements

### Account and connection

- Configuration: HTTPS server URL, username, password, Keep Me Signed In.
- Validate and normalize the URL before storing it.
- Exchange credentials for a revocable token; store tokens and optional credentials only in Keychain.
- Logout clears credentials and lets the user separately choose whether to remove cached audio, metadata, and learning history.
- Never log credentials, tokens, full authenticated URLs, or headers.

### Library and metadata

- Metadata sync is user initiated; incremental sync uses a cursor and tombstones.
- Required track data: stable UUID, title, artist(s), album, album artist, genre(s), language, release year/date, duration, track/disc, explicit flag, artwork identity, audio identity/checksum, codec/bitrate, and server revision.
- Enrichment fields may include tempo/BPM, energy, valence, danceability, instrumental probability, speech probability, religious/spoken-word/content tags, era, mood, and embedding version.
- Unknown fields remain unknown; do not invent values.
- Canonical ID3 is owned by the server. Device-learned taste and context associations live in Core Data, not inside the MP3.

### Start Listening and queue

- Cold start uses user-selected preferences when available, otherwise a deterministic blend of recent additions, popular/playable tracks, broad genre/language coverage, and diversity constraints.
- Warm start ranks locally using time bucket, weekday/weekend, manually selected activity, coarse context, recent history, track affinity, novelty, repetition limits, and current queue coherence.
- Queue size target: 25 tracks; refill when 8 remain.
- Manual Play Next, Play Later, remove, and reorder take precedence over automatic entries.
- Skip, replay, seek, completion, pause, manual selection, and explicit dislike are learning signals with confidence rules.
- Recommendations must include a reason code and model/ranker version.

### Playback

- One audio engine shared across the app.
- Mini player persists above tab content; tap or upward gesture opens Now Playing.
- Controls: play/pause, previous, next, seek, ±15 seconds, volume where Apple permits, route picker, queue, favorite/dislike, activity, and optional visualizer.
- Lock Screen, Control Center, headset, car, and remote commands remain supported.
- On relaunch, restore track, queue, source, position, and paused/playing intent, but never auto-play.
- Prefer a verified cached file, stream only when necessary, and recover gracefully from expired URLs.
- Audio session interruptions, route changes, and phone calls are explicit state transitions.

### Offline

- User quota accepts MB/GB presets and a custom validated value bounded by free disk space.
- Wi-Fi/unmetered-only default; optional cellular use with clear estimated size.
- Pinned downloads are never evicted automatically. Rolling recommendations use LRU plus predicted utility.
- Download manager uses background `URLSessionDownloadDelegate`, supports task restoration, checks checksum, and reconciles orphaned files.
- Metadata and learned taste remain available even after an audio file is evicted.

### Context and activity

- Manual activity selection always works.
- Motion classification is opt-in and sampled briefly rather than continuously.
- HealthKit workout data is opt-in, purpose-specific, event-driven, and available only on supported devices.
- Recommendation needs a place class, not a location trail: home-like, work-like, gym-like, transit-like, outdoors, or unknown. Derive locally where possible and discard coordinates after classification.
- Location collection is off by default. Low Energy Mode uses significant-change/visit signals or a coarse one-shot sample around an active listening transition—not a permanent 1–3 minute timer.
- Audio route records a coarse category such as built-in speaker, wired, Bluetooth, AirPlay, CarPlay, or unknown. Public APIs do not provide reliable AirPods or generic Bluetooth battery percentage.

### Calendar and Ramadan preference

- Store local calendar features: hour bucket, weekday/weekend, season, and optional user calendar mode.
- Offer an opt-in **Ramadan listening preference** with choices: Off, Suggest religious content, Prefer religious content, or Use selected Ramadan playlist.
- The user chooses the playlist and can override it instantly. The app must not infer religion.
- Calculate the Ramadan date window locally from a maintained calendar library/configuration; allow manual correction because local observations can differ.

### Playlists

- Manual and smart playlists are separate types.
- Auto-grow toggle belongs to each playlist and defaults off.
- Auto-grow rules include allowed/excluded genres, language, era/year range, activity, minimum affinity, diversity, maximum additions per week, and approval mode.
- Every automatic addition records a reason and supports undo.

### Share extension

- Accept shared HTTP/HTTPS URLs only.
- Show normalized URL and a single Download/Send to Server action.
- Use an App Group handoff plus shared Keychain token; the extension does not download media itself.
- Server performs import asynchronously and returns an import job ID/status.
- Validate schemes, length, redirect policy, and supported providers. Present legal/availability failures clearly.

### Settings, diagnostics, and export

- Account, Playback, Offline Storage, Personalization, Activity & Sensors, Privacy & Retention, Appearance, Export & Diagnostics, and About sections.
- Retention presets: 7, 30, 90, 365 days, or Until I Delete. Default 90 days for raw events.
- Compacted preference summaries survive raw-event expiry until Reset Learning.
- Export formats: human-readable JSONL/CSV plus a documented schema manifest; optional encrypted ZIP for full sensitive exports.
- Export uses the system share sheet and clearly states whether precise/coarse location is included.

### Appearance and accessibility

- System/light/dark theme, tint/accent options, Dynamic Type, Reduce Motion, VoiceOver, sufficient contrast, keyboard navigation on macOS/iPad, and localization-ready strings.
- Visualizer is optional, disabled under Reduce Motion/Low Energy Mode, and driven from already-decoded audio data where feasible. It must never cause playback underruns.

## 5. Non-functional requirements

- Use Swift concurrency and actors; no unstructured task fan-out from views.
- Background work is cancellable, bounded, and observable.
- Database migrations are versioned, tested, and reversible through backups—not destructive resets.
- Event payloads are schema-versioned and idempotent.
- Target crash-free sessions above 99.8%; playback-start success above 99.5% for valid local files.
- At-rest sensitive exports are protected; local database uses Apple Data Protection where applicable.
- No personal learning data is uploaded by default. A future sync feature requires separate explicit consent and end-to-end privacy design.

## 6. Out of scope for the first public v2 milestone

- Server-side AI or personal-profile learning.
- Continuous precise location trails.
- Reading Bluetooth accessory battery levels through unsupported APIs.
- Autonomous LLM calls during playback.
- Social sharing of listening context, location, fitness, or learned profiles.
- Sample-accurate multi-device synchronized playback.

## 7. Major risks and mitigations

| Risk | Mitigation |
|---|---|
| Sparse cold-start history | Metadata heuristics, diversity, explicit starter preferences, exploration budget |
| Battery drain | Session-scoped sensors, coarse/event-driven location, batching, MetricKit energy tests |
| Sensitive inference | Local-only processing, permission separation, reason codes, reset/export controls |
| Bad or incomplete ID3 | Server validation pipeline, unknown-safe client model, enrichment revision |
| Model degrades experience | Heuristic fallback, shadow evaluation, feature flags, signed rollback |
| Huge libraries | Cursor sync, pagination, indexes, background import, incremental embeddings |
| XCFramework evolution | Stable public protocols/value types, semantic versioning, API compatibility tests |

## 8. Release gates

No phase advances unless tests cover migration, offline playback, restoration, queue priority, background downloads, permission denial, retention deletion, export, and model fallback. Battery, memory, launch, and playback latency budgets must be measured on the minimum supported physical iPhone.
