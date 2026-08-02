# uMusic operations runbook

## Daily checks

1. Verify `/health/ready/`, worker/scheduler state, queue depth, storage free space,
   failed imports, and Cloudflare connector health.
2. Confirm the nightly database fixture, media checksum manifest, and media snapshot
   completed. Keep backup output outside the media tree.
3. Investigate repeated 401/403, checksum failures, continuation-empty spikes, and
   storage write failures without logging tokens or signed URLs.

## Backup and restore

Create the application backup, then snapshot/copy the exact media root:

```bash
docker compose -f compose.prod.yaml exec web \
  python manage.py backup_umusic --output /backups/umusic-YYYY-MM-DD
```

Encrypt off-host copies. Monthly, restore into a new isolated database with the media
snapshot mounted read-only. Never run `flush` or restore against the live database.
The restore is successful only when the fixture loads and every manifest object exists.

## Incident procedures

- **Stolen device:** revoke it in `/library/devices/`; verify its Bearer requests and
  existing signed download URLs return 401.
- **Tunnel token exposure:** rotate it in Cloudflare, replace the server secret, and
  restart only the tunnel service.
- **Django secret exposure:** rotate it, expire browser sessions, restart app services,
  and expect all outstanding signed download URLs to become invalid.
- **Missing/corrupt MP3:** stop imports, preserve logs, restore the checksum-addressed
  object from media backup, and verify its SHA-256 before resuming.
- **Database failure:** stop writers, preserve the failed volume, provision a clean
  database, restore the last verified fixture, verify media, then run health/playback.
- **Queue buildup:** pause new imports, inspect the oldest job/reason, restart workers
  only after dependency health is restored; idempotency keys make retries safe.

## Upgrade and rollback

Take and verify a backup, retain the previous images, inspect migrations, build pinned
images, migrate once, start workers/scheduler/web, then smoke health, login, Range
streaming, sync manifest, and one prepared playback. Roll back application images only
when schema compatibility is documented; otherwise restore through the migration-
specific procedure.

## Offline-workout support checklist

Confirm device token validity, prepare status with zero failed files, free device quota,
local playback of the first and next tracks, airplane mode, lock-screen controls,
phase transition without current-track replacement, deferred event count, and exactly-
once upload after reconnecting.
