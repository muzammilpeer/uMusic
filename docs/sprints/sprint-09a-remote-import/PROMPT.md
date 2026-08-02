# Sprint 09A implementation prompt

```text
Implement a guarded asynchronous remote-import adapter for uMusic. Accept direct
HTTPS MP3 and public YouTube URLs separated by commas or new lines. Persist one
observable item per source, process via Celery, reuse MP3 validation/deduplication,
and expose web/API status. Use pinned yt-dlp and FFmpeg for public YouTube sources
only after operator authorization attestation. Block private/reserved network
targets, credentials, playlists, private/authenticated sources, remote executable
components, DRM bypass, and oversized files. Test mixed success, validation,
idempotency, audit data, and Docker deployment.
```

