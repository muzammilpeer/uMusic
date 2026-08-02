# Sprint 09A — Batch remote music import

## Goal

Extend the backend before iPhone development so an owner can submit comma-separated
or newline-separated public music sources and let the worker import MP3 files.

## Deliverables

- Mixed batches of direct HTTPS `.mp3` URLs and public YouTube URLs.
- Asynchronous Celery processing with per-source status and safe retry behavior.
- Web form and authenticated REST endpoints.
- `yt-dlp` plus FFmpeg MP3 extraction, disabled by default for YouTube.
- Authorization attestation, source provenance, size/item limits, and audit events.
- SSRF protection for direct downloads and no cookies, credentials, private sources,
  playlists, remote components, DRM bypass, or authentication bypass.

## Exit criteria

- A valid batch becomes searchable library tracks or duplicate results.
- One failed URL does not discard successfully imported items.
- Every submitted source has observable pending/running/completed/failed state.
- Existing quality and deployment gates remain green.

