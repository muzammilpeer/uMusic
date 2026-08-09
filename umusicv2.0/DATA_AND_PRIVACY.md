# Local Data, Logging, Privacy, and Export

## Data classification

| Class | Examples | Default handling |
|---|---|---|
| Account secret | password, token | Keychain only; never exported/logged |
| Catalog | title, artist, year, genre | synced locally; server revisioned |
| Behavioral | plays, skips, seeks, repeats | local raw retention 90 days; then aggregate |
| Contextual | activity, time, route category | local, optional where sensitive |
| Highly sensitive | precise location, HealthKit metrics | off by default; minimized; separate consent |
| Learned | song/context affinity, embeddings | local until Reset Learning |
| Diagnostics | errors, durations, model version | sanitized, bounded retention |

## Core Data entities

### Catalog store

- `Track`: `id`, `revision`, title, sort fields, durationMs, releaseDate/year, explicit, language confidence, availability, audio/artwork identities.
- `Artist`, `Album`, `Genre`, `Tag` with normalized many-to-many links.
- `AudioAnalysis`: BPM, pace class, energy, valence, danceability, speech/instrumental scores, analysis/version/confidence.
- `ServerPlaylist` and `ServerPlaylistItem`.

### User store

- `PlaybackSession`: ID, start/end, start reason, initial context ID, queue version, device class.
- `PlaybackObservation`: session/track, start/end, listenedMs, trackDurationMs, completion ratio, start/end positions, skip class, source, manual/automatic, recommendation ID/reason, interaction counts.
- `ContextSnapshot`: time features, activity type/source/confidence, coarse place class, route category, network class, Low Energy Mode, optional workout bucket, calendar mode. No coordinate required.
- `QueueSnapshot` and `QueueItem`: order, origin, insertedAt, manual priority, consumed state.
- `TrackAffinity`: track/context-key score, positive/negative counts, lastUpdated, decay state, confidence.
- `FeatureAggregate`: feature key/value bucket/context, exposure, positive weight, negative weight, mean completion, lastSeen.
- `Playlist`, `PlaylistItem`, `SmartPlaylistRule`, `AutoAdditionAudit`.
- `ModelRegistry`: model ID/version, feature schema, signature, activation/rollback dates, metrics.
- `ConsentRecord`: signal, status, policy version, timestamp.

### Telemetry store

- `EventEnvelope`: event UUID, schema version, monotonic sequence, session ID, type, wall timestamp, monotonic offset, compact payload, export state.
- `DiagnosticEvent`: severity/domain/code, redacted metadata, timestamp.
- `AggregationCheckpoint`: reducer/schema version and last sequence.

## Event envelope

JSON is the export/debug representation; persistence may use typed columns plus a compact binary payload.

```json
{
  "event_id": "019...uuid",
  "schema_version": 1,
  "sequence": 1842,
  "session_id": "uuid",
  "type": "track_ended",
  "occurred_at": "2026-08-09T08:42:11Z",
  "monotonic_ms": 418332,
  "track_id": "uuid",
  "context_id": "uuid",
  "payload": {
    "listened_ms": 201440,
    "duration_ms": 214000,
    "completion_ratio": 0.941,
    "end_reason": "natural_completion",
    "queue_origin": "local_ranker",
    "ranker_version": "heuristic-1",
    "reason_codes": ["morning_affinity", "genre_affinity"]
  }
}
```

Allowed event types: `session_started`, `session_ended`, `track_started`, `track_paused`, `track_resumed`, `track_seeked`, `track_ended`, `track_skipped`, `track_replayed`, `queue_item_added`, `queue_item_removed`, `queue_reordered`, `favorite_changed`, `dislike_changed`, `activity_changed`, `route_changed`, `context_changed`, `recommendation_generated`, `download_state_changed`, and sanitized `error`.

Do not log every playback tick or GPS point. Position is a transient UI value; durable events describe meaningful transitions.

## Context snapshot example

```json
{
  "time_bucket": "morning",
  "local_hour": 8,
  "weekday": 7,
  "is_weekend": true,
  "activity": "walking",
  "activity_source": "manual",
  "activity_confidence": 1.0,
  "place_class": "outdoors",
  "place_confidence": 0.62,
  "route_category": "bluetooth",
  "network_class": "unmetered",
  "energy_policy": "low_energy",
  "calendar_mode": "ramadan_preference",
  "workout_intensity_bucket": null
}
```

Location-derived fields must not contain latitude, longitude, address, geohash, or stable place identifier in the normal recommendation log. A separate developer-only raw-location export mode, if ever built, requires explicit session consent and short retention.

## Signal interpretation

- Natural completion is weak-to-medium positive, not proof of liking.
- Replay, favorite, manual selection, and playlist addition are stronger positive signals.
- Skip before 10 seconds is negative only if playback was audible and not caused by error/interruption.
- Skip after substantial listening is ambiguous.
- Seeking may indicate engagement or avoidance; use direction/count carefully.
- Manual queue entries must not be treated as ranker successes.
- Exposure must be counted so rarely shown tracks are not confused with disliked tracks.

## Efficient collection

- Capture a context snapshot at session start and only when a material field changes.
- Keep current observation in actor memory; update one crash checkpoint every 15 seconds.
- Coalesce repeated seeks/route changes in a short window.
- Save event batches (target 25 events or 120 seconds in Low Energy Mode).
- Aggregate daily or when idle/charging. Delete expired raw rows using Core Data batch deletes.
- Use integers/enums and normalized IDs rather than repeating metadata strings.
- Use calendar/time-zone data at event time so travel does not rewrite historical meaning.

## Retention and compaction

1. Raw events live for the selected 7/30/90/365-day or indefinite period.
2. Before expiry, reducer updates `TrackAffinity` and `FeatureAggregate` with time decay and confidence.
3. Aggregates contain counts/weights, not reconstructable timelines or coordinates.
4. Delete raw rows and expired diagnostic data; checkpoint the reducer atomically.
5. Reset Learning removes aggregates, observations, recommendation history, and model personalization state while preserving catalog/playlists unless the user asks otherwise.

## Export package

```text
umusic-export-YYYYMMDD.zip
├── manifest.json              # app/schema/model versions and redaction level
├── tracks.csv                 # IDs and allowed catalog metadata
├── observations.jsonl
├── contexts.jsonl
├── affinities.csv
├── feature_aggregates.csv
├── recommendations.jsonl
└── diagnostics.jsonl          # sanitized and optional
```

- Offer **Sanitized** (default: no precise location, secrets, server URL, usernames, file paths) and **Full local research** exports with a detailed preview.
- Generate to a protected temporary file, stream rows to avoid memory spikes, optionally encrypt, present system share sheet, then delete the temporary copy after completion/timeout.
- Bundle a macOS `UMusicDataInspector` tool that opens an exported package or a read-only copied store, runs schema checks, and renders tables/charts. Never open the live phone database for mutation.

## Permission copy principles

Ask at the point of value, describe what is collected, how often, how it changes recommendations, and that denial leaves manual controls available. Permission revocation stops collection immediately; previously collected raw data follows the user’s retention/delete choice.

