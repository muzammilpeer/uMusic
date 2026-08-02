# Sprint 01 completion report

- Status: complete
- Completed: 2026-08-02

## Delivered

- Artist, album, artwork, audio file, track, import job, and audit-event models.
- Initial library migration applied to SQLite and PostgreSQL.
- Idempotent owner bootstrap management command.
- Quarantine upload flow with byte limits and sanitized filenames.
- Genuine MP3 validation through ffprobe plus MP3 frame validation through Mutagen.
- ID3 title, artist, album, year, track/disc number, and artwork extraction.
- SHA-256-addressed immutable audio/artwork storage.
- Local Docker-volume and mounted POSIX/GFS/GlusterFS-compatible storage backends.
- Copy, fsync, checksum, atomic publish, path containment, and checksum locking.
- Exact duplicate reuse without duplicate media or track records.
- Transaction rollback and stored-object cleanup on import/storage failure.
- Authenticated upload and import-job APIs.
- Owner-scoped library, import history, import error, and login pages.
- Django admin registration and actionable import statuses/errors.

## Verification

- Ruff formatting/linting: passed.
- Strict mypy: passed for 54 source files.
- Django system check: passed.
- Migration drift check: passed.
- Pytest: 25 passed.
- Coverage: 89%, above the 85% gate.
- Storage contracts: passed for local and mounted implementations.
- Concurrent checksum publish: passed.
- Python 3.13 production image build: passed.
- PostgreSQL `library.0001_initial`: applied.
- FFprobe 5.1.9 available in the production image.
- Web and worker storage health: readable and writable on the shared media volume.
- Self-cleaning MP3 import through Python 3.13, PostgreSQL, FFprobe, Mutagen, and
  local media storage: passed.
- Packaged login template over LAN: HTTP 200.

## Configuration and migrations

- Added `library.0001_initial`.
- Added `UMUSIC_MAX_UPLOAD_BYTES` with a 150 MiB development default.
- Added `UMUSIC_FFPROBE_PATH` with `ffprobe` as the default.
- `UMUSIC_STORAGE_BACKEND` selects `local` or `mounted`.
- FFmpeg/ffprobe and Mutagen are now production dependencies.

## Known limitations deferred by scope

- Import processing is synchronous in Sprint 01; large-job background scheduling
  can be introduced without changing the import service contract.
- Track playback and HTTP byte-range streaming begin in Sprint 02.
- Metadata editing, search, and richer artwork display are later library polish.

## Sprint 02 entry conditions

All Sprint 01 exit criteria are satisfied. Create an owner before interactive use,
then Sprint 02 may begin using [`../sprint-02/PROMPT.md`](../sprint-02/PROMPT.md).

