# Sprint 08 report — Scheduled intelligence and web polish

## Delivered

- Daily Celery Beat refresh and an authenticated manual refresh action.
- Observable, retryable, idempotent operational jobs.
- Operations dashboard for queue depth, storage health, failed imports/adapters,
  active playback, learning state, refresh jobs, and unmatched wanted tracks.
- Database fixture plus media-reference manifest backup and guarded restore commands.
- Responsive navigation, mobile player layout, skip navigation, and keyboard focus styles.
- Synthetic catalog generator and repeatable browse/search performance benchmark.

## Operations

Run a manual backup from the web container:

```bash
docker compose exec web python manage.py backup_umusic --output /backups/umusic-$(date +%F)
```

Restore only into an empty, isolated test deployment first:

```bash
docker compose exec web python manage.py restore_umusic \
  --input /backups/umusic-YYYY-MM-DD --confirm
```

The restore command loads the database fixture and then verifies every recorded
media object through its configured storage backend. Missing MP3 objects fail the
restore check.

## Performance exercise

Generate a disposable 50,000-track fixture and require each primary catalog query
to finish within 500 ms:

```bash
python manage.py benchmark_catalog --generate --size 50000 --max-ms 500
```

Run this against an isolated performance database because generated rows remain in
the catalog for inspection. The command reports active track count plus browse and
search time. The 500 ms value is the Sprint 08 server-side query target; it excludes
network and template-rendering time.

## Verification

- 72 automated tests pass.
- Coverage meets the 85% project gate.
- Ruff formatting/lint, strict mypy, and migration consistency checks pass.
- Backup/restore is exercised against an isolated test database in the suite.

