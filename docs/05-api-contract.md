# API contract outline

All endpoints are versioned under `/api/v1/`. Use JSON except for uploads, audio
streaming, artwork, and manifest file downloads. Generate an OpenAPI document and
treat it as the iOS contract starting in Sprint 9.

## Accounts and devices

- `POST /auth/login`
- `POST /auth/logout`
- `GET /me`
- `GET /devices`
- `POST /devices/register`
- `DELETE /devices/{id}`
- `POST /devices/{id}/rotate-token`

## Library

- `GET /tracks`
- `GET /tracks/{id}`
- `PATCH /tracks/{id}`
- `DELETE /tracks/{id}`
- `POST /imports/uploads`
- `GET /imports/{id}`
- `POST /imports/{id}/retry`
- `GET /artists`
- `GET /albums`
- `GET /search?q=`

## Import adapters

- `GET /adapters/`
- `POST /adapters/folder/`
- `POST /adapters/taste/`
- `POST /adapters/taste/{candidate_id}/confirm/`
- `POST /adapters/youtube/` (disabled by default)
- `POST /adapters/remote/` (comma/newline-separated direct MP3 and YouTube URLs)
- `GET /adapters/jobs/{job_id}/` (batch and per-source status)

Taste matches never authorize audio acquisition. Probable matches require an
explicit confirmation. YouTube requests require the feature flag and a per-job
operator authorization attestation; no credentials or access-control bypasses
are supported.

Remote URL batches return `202`. Each item records its source kind/host and independent
status so partial success is observable. Direct sources must be public HTTPS `.mp3`
URLs. YouTube items require the feature flag and operator authorization attestation;
playlists, credentials, cookies, private sources, and access-control bypasses are not
supported.

## Playback

- `GET /tracks/{id}/stream`
- `POST /playback/sessions/`
- `GET|PATCH /playback/sessions/{id}/`
- `PATCH /playback/sessions/{id}/queue/`
- `GET /events/`
- `POST /events/batch/`

Event batches contain up to 500 events and return `202` with `accepted`,
`duplicates`, and stable server `event_ids`. Idempotency is scoped by owner and
`client_event_id`. Client clock skew and offline ordering never overwrite the
original `client_timestamp`; derived facts sort by client time and use server
receipt time as a stable tie-breaker.

Progress heartbeats are emitted every 15 seconds while playing. A single event
can contribute no more than 30 seconds of listening time. Seeking contributes no
listening time. Completion is explicit or inferred at 90% position; a skip at or
below 20% is early. Raw events are append-only. Run
`python manage.py rebuild_play_facts` to recreate all disposable summaries.

Audio range behavior must be integration-tested separately from the OpenAPI JSON
contract.

## Contexts

- `GET|POST /contexts/activities/`
- `GET|POST /contexts/geofences/`
- `GET|PATCH|DELETE /contexts/geofences/{id}/`
- `POST /contexts/snapshots/`
- `POST /contexts/geofences/{id}/forget-learning/`

Coordinates are accepted only when creating/editing a geofence. Playback context
payloads use its ID.

Deleting a geofence removes its coordinate-bearing record and creates an audit
and forget marker. Existing immutable snapshots retain the opaque geofence UUID
and display name but never copy coordinates. Manual selection requires no
browser or device location permission.

## Playlists and recommendations

- `GET|POST /playlists/`
- `GET|PATCH|DELETE /playlists/{id}/`
- `POST /recommendations/session-playlist/`
- `GET /recommendations/generated-playlists/{id}/`
- `POST /recommendations/generated-playlists/{id}/regenerate/`
- `POST /recommendations/generated-playlists/{id}/replace-track/`
- `POST /playback-sessions/{id}/continuations`
- `GET /recommendations/tracks/{id}/explanation/`
- `GET /learning/affinities/`
- `POST /learning/rebuild/`
- `POST /learning/reset/`

Affinities expose target and context identity, normalized score, confidence,
positive/negative evidence, sample count, explicit override, reason-code details,
last observation, and algorithm version. Rebuild responses include a canonical
evidence digest so identical source data can be checked for determinism.

Example generation request:

```json
{
  "activity_id": "cycling",
  "geofence_id": "optional-uuid",
  "duration_minutes": 75,
  "target_energy": 0.8,
  "discovery": 0.25,
  "offline": true,
  "seed": 41728
}
```

Example selected-track explanation:

```json
{
  "track_id": "uuid",
  "score": 0.87,
  "model_version": "rules-v3",
  "reasons": [
    {"code": "LIKED_ARTIST", "contribution": 0.24},
    {"code": "CYCLING_COMPLETIONS", "contribution": 0.18},
    {"code": "ENERGY_PHASE_MATCH", "contribution": 0.15}
  ]
}
```

## Offline synchronization

- `POST /devices/{id}/sync-plans`
- `GET /sync-plans/{id}`
- `GET /sync-plans/{id}/manifest`
- `POST /sync-plans/{id}/acknowledge`
- `POST /devices/{id}/events/batch`

Queue continuation requests include activity/context, played track IDs, current
queue IDs, locally cached track IDs, desired count or duration, and the active
recommendation version. Responses contain an ordered continuation, reason codes,
and short-lived stream/download authorization. Clients should request early
enough to tolerate network latency but must never require continuation for a
prepared offline session.

Example continuation request:

```json
{
  "remaining_track_ids": ["uuid-1"],
  "played_track_ids": ["uuid-2", "uuid-3"],
  "cached_track_ids": ["uuid-4"],
  "desired_duration_minutes": 30,
  "context_snapshot_id": "uuid-5"
}
```

Manifest entries include stable track ID, playlist position, file size, SHA-256,
download URL/token, metadata version, and artwork checksum. Download URLs expire;
the manifest identity does not.

## Error format

```json
{
  "error": {
    "code": "INVALID_AUDIO_FORMAT",
    "message": "Only MP3 audio is accepted.",
    "request_id": "uuid",
    "details": {}
  }
}
```

Never make mobile clients parse human-readable messages to determine behavior.
