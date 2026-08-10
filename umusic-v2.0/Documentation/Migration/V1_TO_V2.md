# Optional v1 to v2 Migration

## Safety boundary

Sprint 18 introduces `UMusicMigration`, a copy-first adapter that consumes a user-selected v1 export directory. It never opens a live v1 store, reads Keychain credentials, moves cached media, or writes into the source directory. Its output is a validated migration package; importing that package into live v2 stores is deliberately deferred until the host app has a reviewed commit coordinator and user interface.

The source directory may contain only these fixed file names:

| File | Supported content |
|---|---|
| `catalog.json` | Stable track ID, title, artist, album, genre, language, year, duration |
| `queue.json` | Ordered stable track IDs |
| `pending-events.json` | Stable event/song IDs, timestamps, progress, completion, explicit activity |
| `settings.json` | Offline quota, retention days, cellular preference |

Credentials, server URLs, device identifiers, stream URLs/paths, cached audio, raw output-route values, raw HealthKit samples, and unknown fields are explicitly unsupported and are recorded in the manifest rather than copied.

## Workflow and commit boundary

1. The user exports or selects a v1 snapshot. The adapter performs no discovery of live v1 locations.
2. Preflight verifies required files and free space, then hashes every source file.
3. Each phase writes protected files to a uniquely named `.staging` directory and atomically updates `checkpoint.json`.
4. Stable v1 UUIDs map identically to v2 UUIDs. Counts and SHA-256 hashes are recorded in `manifest.json`.
5. Before completion, every source hash is rechecked and every output is decoded, counted, and rehashed.
6. The staging directory is atomically renamed to `.ready`. That rename is the migration-package commit boundary; it is **not** a live-store import.

Retry is idempotent: an intact `.ready` package is validated and returned, while an interrupted staging package resumes from its checkpoint. A changed source or corrupt output fails closed.

## Recovery and rollback

Rollback requires an explicit confirmation value and can remove only the adapter's named, incomplete staging directory. It refuses to remove a completed `.ready` package and never deletes anything in v1. Low disk, denied access, corrupt JSON, interruption, changed inputs, corrupted outputs, retry, and rollback scope are covered by automated fixtures.

Before a production migration UI is enabled, add a live-store import transaction, account-namespace selection, user preview/confirmation, protected backup, post-import count/hash reconciliation, and signed-device recovery drill. Until then, the package target is an engineering adapter, not an advertised end-user migration feature.
