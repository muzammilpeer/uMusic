# Deployment and operations

## Target deployment

Use Docker Compose on the local server. Initial services:

- `web`: Django ASGI/WSGI application;
- `worker`: Celery worker;
- `scheduler`: Celery beat;
- `postgres`: primary database;
- `redis`: task broker/cache;
- `proxy`: HTTPS termination and internal MP3 delivery.

## Media storage modes

`UMUSIC_STORAGE_BACKEND` selects the implementation without changing library or
streaming code:

- `local`: Docker named volume or bind-mounted host directory;
- `mounted`: a host/orchestrator-mounted POSIX shared filesystem made visible to
  every web and worker container, including GFS/GlusterFS-style storage.

Local storage is the recommended first deployment. For shared storage, mount the
filesystem on the host, pass the same container path to web and workers, and use
a read-only mount for the proxy where practical. The database stores logical
object keys rather than host paths. Health checks must verify readability,
writability where required, free capacity, and a small create/read/delete probe.

Do not split recommendation or import code into independent services initially.

## Persistent data

Keep separate volumes/directories for:

- PostgreSQL data;
- original MP3 storage;
- artwork;
- quarantine/temporary imports;
- logs if not shipped elsewhere;
- encrypted backups.

Quarantine is disposable. The database and checksum-addressed media are not.

## Configuration

Required categories:

- Django secret and allowed hosts;
- database and Redis connection settings;
- media/quarantine roots;
- storage backend ID, logical media root, and storage health thresholds;
- upload size and duration limits;
- worker concurrency;
- public base URL;
- trusted proxy configuration;
- import-adapter feature flags;
- optional OAuth credentials;
- backup destination and retention.

Commit an `.env.example`, never a populated `.env`.

## Network access

The production profile uses an outbound-only Cloudflare Tunnel, with Cloudflare
terminating HTTPS and no origin application port exposed. Follow
[09-cloudflare-zero-trust.md](09-cloudflare-zero-trust.md). Retain uMusic's scoped
device authentication behind the tunnel; edge identity is an additional control and
does not replace application authorization.

## Backup plan

At minimum:

- nightly PostgreSQL logical backup;
- media backup or replicated filesystem snapshot;
- manifest containing media checksums;
- configuration backup excluding renewable secrets;
- documented monthly restore test.

A database-only backup is insufficient because it cannot reconstruct the MP3
library. A media-only backup loses preferences, events, playlists, and learning.

Create an application-level database and media-reference backup with:

```bash
python manage.py backup_umusic --output /backups/umusic-YYYY-MM-DD
```

For a production bind mount, create `UMUSIC_BACKUP_PATH` in advance and grant the
container application user (UID 100 by default) write access. The development Compose
file uses a persistent named backup volume.

Copy or snapshot the actual media storage alongside that directory. Test restoration
in an isolated deployment; the explicit confirmation guard prevents accidental use:

```bash
python manage.py restore_umusic --input /backups/umusic-YYYY-MM-DD --confirm
```

The restore verifies that every MP3 referenced by the restored database exists in
the selected local or mounted/GFS-compatible storage backend.

## Observability

Expose authenticated operational views and machine health endpoints for:

- database/Redis connectivity;
- queue length and oldest job age;
- failed imports and reason codes;
- free/used storage;
- missing or checksum-invalid media;
- streaming error rate;
- recommendation latency and failures;
- storage read latency and rolling/server cache hit rates;
- queue-continuation requests, latency, and empty responses;
- mobile sync failures;
- last successful backup and restore test.

Never log device coordinates, OAuth tokens, signed download URLs, passwords, or
full external-source query strings.

## Upgrade procedure

1. Read release notes and migration plan.
2. Create and verify a fresh backup.
3. Pull/build pinned images.
4. Run migration compatibility checks.
5. Stop writers briefly when required.
6. Apply database migrations.
7. Start workers, scheduler, then web.
8. Run health and playback smoke tests.
9. Retain the previous image for application rollback.

Database rollback must use a migration-specific procedure; never assume rolling
back an image reverses a schema migration.

## YouTube MP3 metadata

When the explicitly enabled and operator-attested YouTube importer is used, yt-dlp
extracts and embeds the available thumbnail and source metadata. uMusic normalizes
track/title, singer/artist (artist, creator, uploader, then channel), album (including
playlist fallback), album artist, release/upload date, genre/categories/tags, track
and disc numbers, YouTube video ID, and source URL into ID3v2.3 before ingestion.
Missing fields remain empty rather than being invented. Imported files receive a
sanitized `Singer - Song.mp3` display/download filename.

Any stored track can be corrected from its web detail page. Saving edits rewrites the
ID3 tags inside the MP3, publishes a new checksum-addressed object, updates the sync
checksum and library relationships, audits the change, and deletes the obsolete media
object only after the database transaction succeeds. Offline devices receive the new
file on their next manifest sync.
