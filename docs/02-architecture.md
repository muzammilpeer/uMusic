# Architecture

## Shape

Start as a modular Django monolith. Celery workers handle slow or scheduled jobs.
This keeps deployment understandable while enforcing internal boundaries that
can be separated later if scale ever requires it.

```text
Browser / future iPhone
          |
     HTTPS / REST
          |
  Django application
  | auth       | library       | playback |
  | events     | contexts      | playlists|
  | recommender| imports       | sync     |
          |
  PostgreSQL + Redis + MP3 storage
          |
      Celery workers
```

## Django applications

- `accounts`: users, devices, API tokens, preferences.
- `library`: tracks, artists, albums, files, artwork, metadata, duplicate checks.
- `playback`: queues, playback sessions, streaming authorization, range responses.
- `events`: append-only listening events and aggregation jobs.
- `contexts`: activities, geofences, workout phases, context snapshots.
- `playlists`: manual, smart, generated, and immutable session playlists.
- `recommendations`: candidates, scoring, explanations, model versions, evaluation.
- `imports`: uploads, watched folders, taste imports, and optional source adapters.
- `sync`: devices, manifests, file checksums, download state, event reconciliation.
- `operations`: health, storage, job status, backup metadata, audit log.

## Storage

The application uses a storage interface rather than direct absolute paths. The
first implementation must provide:

- `LocalFilesystemStorage`, backed by a bind mount or named Docker volume;
- `MountedSharedFilesystemStorage`, backed by a POSIX-compatible mount exposed
  inside the container, including GFS/GlusterFS-style deployments.

Both implementations use identical checksum keys and atomic publish semantics.
Django does not mount or administer the shared filesystem; the Docker host or
orchestrator mounts it and passes a configured media root into the containers.
Database records store a storage backend ID and object key, never a host-specific
absolute path. Web and worker containers must see the same media namespace.

The storage interface must cover quarantine publish, open/read, existence, size,
checksum verification, deletion, and health/capacity reporting. Do not assume
that cross-filesystem rename is atomic: publish by copy-to-temporary-key, verify,
then rename within the destination filesystem. Use a database/import lock to
prevent two workers from publishing the same checksum simultaneously.

Original MP3 files are immutable after successful import. Store them by checksum,
not by user-provided filename:

```text
media/audio/sha256/ab/cd/<full-sha256>.mp3
media/artwork/sha256/12/34/<full-sha256>.jpg
```

Metadata edits update database records and do not rewrite the original file in
the first release. A later explicit “write tags to file” operation can create a
new version safely.

## Upload pipeline

1. Stream upload to quarantine with a size limit.
2. Confirm extension and MIME hints.
3. Inspect content with ffprobe; reject anything not identified as MP3 audio.
4. Calculate SHA-256 and detect exact duplicates.
5. Extract ID3 tags, duration, bitrate, sample rate, and artwork.
6. Validate that duration and audio stream are usable.
7. Move to checksum-addressed storage.
8. Create database records transactionally.
9. Schedule analysis and search indexing.

Do not trust extensions or browser MIME types. Never pass an unescaped filename
into a shell command.

## Streaming

The streaming endpoint must support authenticated HTTP byte-range requests,
including `206 Partial Content`, `Content-Range`, `Accept-Ranges`, and correct
cache headers. Development may use Django for file responses; production should
use an internal redirect mechanism through a reverse proxy so application
workers do not spend their time serving audio bytes.

### Streaming and cache pools

Use three distinct concepts:

1. **Prepared offline pool:** immutable session tracks downloaded before leaving.
2. **Rolling device cache:** bounded least-recently-used cache for streamed and
   prefetched MP3 files; pinned/prepared files are never evicted mid-session.
3. **Server/proxy cache:** optional cache for hot byte ranges or complete immutable
   checksum-addressed MP3 objects, especially useful with shared/remote storage.

When fewer than a configurable number of playable tracks remain, a connected
client asks the recommendation service to extend its queue. The server excludes
already played, queued, cached, disliked, and recently skipped tracks, then
returns continuation entries and short-lived download/stream authorization. The
client streams the immediate next track and prefetches subsequent entries. Cache
complete MP3 objects when possible; partial downloads remain temporary until a
checksum validates them.

Queue exhaustion is not an error. If the server or network is unavailable, the
client uses locally compatible cached tracks. Never interrupt the track currently
playing merely to replace the queue.

## Web player

The first UI uses Django templates and HTMX, with a small TypeScript/JavaScript
audio controller. This avoids committing to a separate frontend build before the
domain and API settle. The player owns one HTML audio element and persists queue
state locally and on the server. Use the browser Media Session API when present.

## Recommendation execution

The request path retrieves already-computed features and affinities, produces a
candidate pool, applies hard filters, scores candidates, then runs a sequencing
pass. Feature computation and affinity aggregation occur asynchronously.

## Optional import adapters

Every external source implements a narrow interface:

```python
class AudioImportAdapter(Protocol):
    def inspect(self, source: str) -> ImportPreview: ...
    def fetch_authorized_audio(self, job: ImportJob) -> TemporaryAudio: ...
```

Adapters must finish by passing their result through the same MP3 validation,
checksum, metadata, and audit pipeline as direct uploads.

An optional private YouTube adapter may use a maintained Python/open-source
downloader, but it must be feature-flagged off by default and display an operator
attestation that the content is owned by the user, licensed for download, public
domain, or otherwise authorized. Do not build DRM, login, paywall, age-gate, or
regional-restriction bypass logic. YouTube metadata/taste import is a separate
adapter and must not imply permission to copy audio.

## Security boundaries

- Private deployment does not remove the need for authentication.
- CSRF protection remains enabled for browser requests.
- Mobile clients use scoped, revocable device tokens.
- Import jobs cannot read arbitrary server paths.
- Location/context data is private and excluded from normal logs.
- All deletions create an audit entry.
- Secrets live outside Git and outside images.
- Rate-limit login, upload initiation, streaming token creation, and import jobs.
