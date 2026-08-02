# Sprint 09A report — Batch remote music import

## Delivered

- `/library/adapters/` form accepting comma-separated or newline-separated URLs.
- `POST /api/v1/adapters/remote/` returning `202` with a queued batch job.
- `GET /api/v1/adapters/jobs/{id}/` returning job and per-source results.
- Mixed direct MP3 and YouTube batch classification.
- Celery worker processing with partial-success status, audit event, and imported count.
- Existing quarantine, MP3 validation, checksum storage, and duplicate handling reused.
- Pinned `yt-dlp 2026.6.9` and FFmpeg audio extraction.

## Guardrails

- YouTube remains disabled unless `UMUSIC_YOUTUBE_IMPORT_ENABLED=true`.
- Every YouTube batch requires an explicit ownership/license authorization attestation.
- YouTube playlists, cookies, credentials, config files, and remote components are disabled.
- Direct sources require credential-free HTTPS URLs ending in `.mp3`.
- DNS targets resolving to loopback, private, link-local, reserved, or otherwise
  non-global addresses are rejected on submission and again during download.
- Each download and batch has configurable size/item limits.
- Errors stored for display contain only an exception category, not signed URLs or
  downloader output that could contain secrets.

## Configuration

```env
UMUSIC_REMOTE_IMPORT_ENABLED=true
UMUSIC_REMOTE_IMPORT_MAX_ITEMS=50
UMUSIC_YOUTUBE_IMPORT_ENABLED=false
```

Enable YouTube only when you intend to submit public sources you are authorized to
download. This adapter does not bypass source access controls.

## Verification

- 78 tests pass.
- Coverage meets the 85% gate.
- Ruff, strict mypy, migration consistency, and production Compose validation pass.

The iPhone sprint remains intentionally paused until the owner explicitly approves it.
