# Backend and operations

## Map

- `config/`: Django settings, URLs, Celery configuration.
- `umusic/apps/library/`: MP3 models/import, metadata, storage, portal, track API/deletion.
- `umusic/apps/playlists/`: owned playlists and PATCH track membership.
- `umusic/apps/events/`: idempotent listening events and learned facts.
- `umusic/apps/recommendations/`, `contexts/`, `playback/`, `offline/`: adaptive sessions and sync manifests.
- `docker-compose.yml`, `Dockerfile`: local/production-like stack. Persistent volumes contain database, media, quarantine, backups, and Redis data.

## API/client contracts

- Auth uses Bearer device tokens. Do not log or document credentials.
- Tracks: `GET /api/v1/tracks`; detail/delete: `/api/v1/tracks/<uuid>`.
- Playlists: `/api/v1/playlists/` and `/api/v1/playlists/<uuid>/`.
- Track deletion requires `request.user.is_superuser`, uses `remove_track_from_library`, returns 204, and must preserve history/audit the removal.
- Streaming/download URLs and JSON coding keys are contracts with Swift models; update both sides and tests together.
- Swift/Foundation may encode UUIDs in uppercase. Lowercase client path segments and
  normalize UUID request bodies server-side; invalid IDs return controlled 400/404
  responses rather than dictionary `KeyError` failures.
- Signed media URL expiry is currently one week; treat authorization revocation as a
  separate control and test both.

## Storage/deployment

- Keep storage access behind the media-storage abstraction; support local filesystem and GFS-style implementations without leaking backend paths.
- Never delete or recreate named Docker volumes during ordinary deployment.
- Source is baked into Docker images (not bind-mounted). After backend edits:

```sh
docker compose build web
docker compose up -d web
curl -fsS http://127.0.0.1:8000/health/ready/
docker compose ps web
```

- Rebuild worker/scheduler only when their imported code or task behavior changed.
- Expected hosts include localhost, LAN addresses, and `umusic.muzammilpeer.uk`; production HTTPS terminates through Cloudflare Zero Trust.
- Treat `.env`, `.env.production`, tokens, passwords, and Cloudflare configuration as secrets. Preserve user changes.
- Production image omits pytest. Use development pytest when available and supplement a
  production-only fix with a disposable API-level regression probe plus cleanup.
