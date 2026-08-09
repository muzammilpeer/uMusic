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
    "language": {"code": "ur", "confidence": 0.96},
    "release_date": "1998-01-01",
    "release_year": 1998,
    "duration_ms": 214000,
    "track_number": 2,
    "disc_number": 1,
    "explicit": false,
    "content_tags": ["religious", "spoken_translation"],
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

The client commits a page before advancing its local cursor. Full resync uses a new staging store then swaps only after validation.

## Media

- `POST /api/v2/media/playback-tickets` with track IDs returns expiring stream/download URLs, checksum, byte length, range support, and expiry.
- `GET /api/v2/artwork/{id}` supports ETag and size variants.
- Client verifies media identity/checksum before marking offline-ready.

## Playlists

- `GET /api/v2/playlists/changes?cursor=...`
- `POST /api/v2/playlists`
- `PATCH /api/v2/playlists/{id}` with optimistic `revision`
- `POST /api/v2/playlists/{id}/items:batch`

Personal smart rules and learned auto-growth remain device-local unless a later explicit sync design is approved. If a local playlist is mirrored, the server receives final membership—not private context/reason data.

## Remote import

### `POST /api/v2/import-jobs`

```json
{
  "source_urls": ["https://example.invalid/watch/..."],
  "requested_metadata_policy": "extract_and_validate"
}
```

Returns `202` with `job_id`, state, and status URL. The extension never sends device telemetry with the URL. The server validates source policy, retrieves media, normalizes MP3/ID3, analyzes metadata, and exposes progress/failure codes.

## Device telemetry

No personal listening/context upload endpoint exists in the default v2 contract. Diagnostics upload, if added, must be opt-in, redacted, separately documented, and must never include credentials, precise location, HealthKit values, or raw listening timelines by default.

## Contract validation

- Publish JSON Schema/OpenAPI fixtures with required/optional/nullability rules.
- Generate decoding compatibility tests from golden responses.
- Unknown enum values decode to `.unknown(rawValue)` and do not crash sync.
- API evolution is additive within v2; breaking changes require a new version/capability.

