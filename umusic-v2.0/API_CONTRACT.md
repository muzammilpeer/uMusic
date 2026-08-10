# Client–Server API Contract

The server is an authenticated catalog and media service, not the personal recommendation engine. Contracts are versioned under `/api/v2`. JSON uses snake_case, UTC RFC 3339 timestamps, stable UUIDs, and explicit nullable fields.

## Common rules

- HTTPS required except explicitly enabled local-development hosts.
- Bearer access token plus refresh-token rotation; idempotency key for mutations/imports.
- `ETag`/`If-None-Match` for metadata and artwork; cursor pagination for sync.
- Error body: `code`, `message`, `field_errors`, `retryable`, `request_id`.
- Audio URLs are short-lived signed URLs; never persist authorization query data in logs.
- Server deletions arrive as tombstones; historical local observations retain stable track ID and safe snapshot metadata.

## Authentication

`GET /api/v2/bootstrap` is reachable before session creation and returns only non-sensitive server compatibility metadata. It does not return catalog rows or user data.

### `POST /api/v2/auth/session`

```json
{
  "username": "user@example",
  "password": "<never logged>",
  "device": {"installation_id": "uuid", "platform": "ios", "app_version": "2.0.0"}
}
```

```json
{
  "access_token": "opaque",
  "expires_at": "2026-08-09T10:00:00Z",
  "refresh_token": "opaque",
  "user": {"id": "uuid", "display_name": "M"},
  "capabilities": ["catalog_sync", "audio_stream", "remote_import"]
}
```

Keep Me Signed In controls Keychain persistence; it is not sent as server policy.

### `POST /api/v2/auth/session/refresh`

```json
{"refresh_token": "opaque"}
```

Returns the same session response shape with rotated access and refresh tokens. A `401` expires the local session; a `403` marks it revoked. The client clears persisted tokens in both cases.

## Bootstrap

### `GET /api/v2/bootstrap`

Returns server identity, API/schema versions, user-safe capabilities, library revision/count, supported audio/import types, and maximum page size. It returns no recommendation profile.

## Catalog sync

### `GET /api/v2/library/changes?cursor={cursor}&limit=500`

```json
{
  "schema_version": 1,
  "library_revision": "18491",
  "next_cursor": "opaque-or-null",
  "has_more": true,
  "tracks": [{
    "id": "uuid",
    "revision": 18,
    "title": "Track",
    "artists": [{"id": "uuid", "name": "Artist"}],
    "album": {"id": "uuid", "title": "Album", "album_artist": "Artist"},
    "genres": ["genre-id"],
    "language": "ur",
    "release_date": "1998-01-01",
    "release_year": 1998,
    "duration_ms": 214000,
    "track_number": 2,
    "disc_number": 1,
    "explicit": false,
    "content_tags": ["religious", "spoken_translation"],
    "content_classifications": [
      {"category": "quranTranslation", "confidence": 0.94}
    ],
    "audio_analysis": {
      "version": "analysis-2",
      "bpm": 92.3,
      "energy": 0.31,
      "valence": 0.44,
      "danceability": 0.12,
      "instrumental_probability": 0.08,
      "speech_probability": 0.81
    },
    "artwork": {"id": "sha256", "etag": "etag"},
    "audio": {"id": "sha256", "bytes": 6543210, "mime_type": "audio/mpeg", "bitrate_kbps": 256},
    "available": true
  }],
  "tombstones": [{"track_id": "uuid", "revision": 19, "deleted_at": "2026-08-08T10:00:00Z"}]
}
```

`content_classifications` is optional, explicit server metadata. Supported Sprint 12
categories are `quran`, `quranTranslation`, and `religious`; confidence is clamped to
`0...1`. Missing, unknown, or low-confidence classifications do not match smart
playlist rules. The client never derives these categories from language, identity,
location, or listening behavior.

The signed cursor is opaque and represents either a fixed pagination snapshot or the next sync boundary. Clients must not inspect or edit it. The client commits each page and its cursor in one local transaction before requesting the next page. A completed response still returns a cursor for the next explicit sync. Full resync uses a new staging store then swaps only after validation.

## Media

### `POST /api/v2/media/playback-tickets`

```json
{"track_ids": ["uuid"]}
```

```json
{
  "tickets": [{
    "track_id": "uuid",
    "url": "https://server/api/v2/media/tracks/uuid/stream?ticket=opaque",
    "expires_at": "2026-08-09T10:05:00Z",
    "checksum": "sha256",
    "bytes": 6543210,
    "supports_ranges": true
  }]
}
```

Tickets expire after five minutes, are restricted to the authenticated user and requested track, and can be passed directly to the system media player without exposing a bearer token. Ticket streams support HTTP byte ranges.

- `GET /api/v2/artwork/{id}` supports ETag and size variants.
- Client verifies media identity/checksum before marking offline-ready.

## Playlists

- `GET /api/v2/playlists/changes?cursor=...`
- `POST /api/v2/playlists`
- `PATCH /api/v2/playlists/{id}` with optimistic `revision`
- `POST /api/v2/playlists/{id}/items:batch`

Personal smart rules and learned auto-growth remain device-local unless a later explicit sync design is approved. If a local playlist is mirrored, the server receives final membership—not private context/reason data.

## Remote import

### `POST /api/v1/adapters/remote/` (Sprint 15 compatibility endpoint)

```json
{
  "url": "https://example.invalid/audio.mp3",
  "idempotency_key": "uuid",
  "attested": true
}
```

Returns `202` for a new job and the existing job with `200` when the same authenticated
owner repeats an idempotency key. Status is available from
`GET /api/v1/adapters/jobs/{job_id}/`. The request contains no device telemetry,
context, credentials, playlist, or listening information. The server validates public
HTTPS targets and every redirect, applies provider/authorization policy, retrieves
media asynchronously, normalizes MP3/ID3, and returns stable availability errors.

The future `/api/v2/import-jobs` shape may be additive, but must preserve owner-scoped
idempotency and the privacy boundary above.

## Device telemetry

No personal listening/context upload endpoint exists in the default v2 contract. Diagnostics upload, if added, must be opt-in, redacted, separately documented, and must never include credentials, precise location, HealthKit values, or raw listening timelines by default.

## Contract validation

- Publish JSON Schema/OpenAPI fixtures with required/optional/nullability rules.
- Generate decoding compatibility tests from golden responses.
- Unknown enum values decode to `.unknown(rawValue)` and do not crash sync.
- API evolution is additive within v2; breaking changes require a new version/capability.
