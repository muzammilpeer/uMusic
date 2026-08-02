# Playback and sync troubleshooting

## Fast triage

1. Reproduce the exact client action and record endpoint/status.
2. Inspect `docker compose logs --tail=200 web`; include worker logs for imports/tasks.
3. Separate download failure from later acknowledgement/playback-session failure.
4. Compare Swift request paths and coding keys with Django URLs/serializers.
5. Test the smallest failing request inside the running web container and clean up any
   disposable database record.
6. Patch source, run proportional checks, rebuild only affected services, and verify
   `/health/ready/` before retrying the app.

## Known signatures

- UUID endpoint `404`: inspect uppercase path UUIDs. Swift paths should use
  `uuidString.lowercased()` and Django retains case-insensitive UUID matching.
- Playback session `500` with `KeyError`: normalize every submitted track UUID before
  creating the track dictionary, queue items, or continuation exclusion set.
- Full Resync downloads work but final action fails: inspect acknowledgement and
  `/api/v1/playback/sessions/` independently; do not redownload files unnecessarily.
- Home song is slow although downloaded: verify player and download UI use
  `OfflineManager.shared`; local lookup must happen before refreshing a stream URL.
- "Completion handler blocks are not supported in background sessions": async
  `download(for:)` is using an incompatible background configuration. Keep the current
  foreground session or implement a delegate-based background downloader.
- Saved song metadata appears but Play does nothing: inspect local file/index presence,
  AVAsset playability, saved seek bounds, and fresh signed URL fallback separately.

## Verification

- Compile changed Python modules and run Django `check`.
- Run focused development tests when pytest is installed.
- For production-only data shape/case bugs, make a disposable authenticated API probe,
  assert its status/payload, and delete its session/queue artifacts.
- Build both generic iOS and macOS targets after shared Swift changes.
- State whether the change was merely committed locally or actually rebuilt/deployed.
