# Backup and Restore Runbook

`ReleaseBackupCoordinator` snapshots only fixed v2 store names. The host must first pause playback checkpoints, sync writes, downloads, and learning reduction. SQLite database, WAL, and SHM files are copied as one quiesced set.

## Backup

1. Quiesce all writers and record the build/schema freeze manifest.
2. Call `createSnapshot(from:at:)` with separate store and archive roots.
3. Retain the resulting protected `.ready` archive only after manifest validation succeeds.
4. Copy the archive off-device using an approved protected destination.

## Restore drill

1. Use a clean, empty destination; live data is never overwritten.
2. Call `restoreSnapshot(from:toEmptyStoreRoot:)`.
3. The archive is SHA-256 and byte-count validated before any destination write.
4. The complete staged tree is moved into place atomically.
5. Open catalog, queue, playlists, learning, and offline index through their normal readers; compare counts and perform cached playback.

The automated drill covers a valid round trip, nested offline index, overwrite refusal, corruption rejection, and absence of partial restored files. A signed-device drill with real Core Data WAL state and file protection remains mandatory before release.
