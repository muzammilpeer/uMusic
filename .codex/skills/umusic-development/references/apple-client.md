# Apple client map and invariants

## Key files

- `UMusicApp.swift`: shared `SessionStore`/`AudioPlayer`, scene lifecycle persistence.
- `AudioPlayer.swift`: AVPlayer, remote commands, Now Playing, queue continuation, event batching, restore.
- `QueueStore.swift`: persisted queue and playback snapshot.
- `LibraryView.swift` / `LibraryViewModel.swift`: sidebar, local library cache, manual Sync, mini/full player, playlist/server deletion.
- `OfflineManager.swift` / `OfflineView.swift`: MP3 index, background downloads, quota, eviction, per-track status/deletion.
- `WorkoutView.swift`: activity configuration and prominent top Start/Finish control.
- `HealthWorkoutService.swift`: HKWorkoutSession and event-driven workout metrics.
- `LocationContextService.swift`: low-energy, workout-scoped location.
- `ActivityDetectionService.swift`: user-requested short Core Motion sample.
- `UMusicShareExtension/ShareViewController.swift`: accepts YouTube URLs from the iOS/macOS
  Share sheet and queues the existing authenticated remote-import API.

## Required behavior

- Restore the last track synchronously from local state so the bottom player is visible immediately. Attach cached/remote media after credentials are configured. A Play tap during restoration must resume after preparation.
- Persist track snapshot, queue, seek, offline state, and playback state on track changes, seek, pause/resume, 15-second heartbeat, and scene inactivity/background.
- Prefer cached MP3 for every play, even if the previous session streamed it.
- Keep `OfflineManager.shared` as the default instance used by `AudioPlayer` and
  `OfflineViewModel`; separate live indexes cause a network fallback after download.
- Do not auto-sync library metadata. Search the cached list locally; top-right Sync fetches and replaces the cache.
- Continue remote recommendations only near queue end, throttle retries, and respect Wi-Fi-only downloads.
- Keep Now Playing/Lock Screen standard controls: play/pause, next/previous, seek, ±15 seconds, title/artist/duration/activity.

## Energy/privacy

- System Low Power Mode cannot be enabled by an app. `AppEnergyPolicy` is the app policy and defaults true.
- Motion never starts just by opening Now Playing/Workout. User-triggered sampling is 5 seconds in low-energy mode; stop after a confident match.
- Without raw-route opt-in, request one coarse outdoor workout location and stop. Indoor activity uses no GPS.
- With raw-route opt-in, use automatic pauses and coarse distance filters; low-energy mode uses kilometre accuracy/500 m.
- HealthKit live workout updates are event-driven; stop sessions and sensors when the user finishes.
- Batch listening telemetry (120 seconds in low-energy mode; immediate on pause/completion).

## Apple limitations

- Public iOS APIs expose the audio route but not AirPods/generic Bluetooth headset battery percentage. Direct users to Control Center; do not add BLE scanning as a fake workaround.
- Standard Lock Screen media UI cannot host arbitrary workout stats/buttons. Use an ActivityKit Widget extension for a future throttled Live Activity.
- Do not auto-play restored audio at launch.
- Attach the mini player safe-area inset to detail content so all final rows remain
  reachable. Apply interactive keyboard dismissal to every text-entry scroll view.
- Do not use async completion-handler `URLSession.download(for:)` with a background
  session configuration. A background implementation requires
  `URLSessionDownloadDelegate` and task restoration.
- The Share Extension reads the device token through the shared keychain access group on
  iOS and macOS. Preserve legacy-token migration in both containing-app builds.
- Keep unsupported controls out of macOS UI: HealthKit and Core Motion classification
  are iPhone-specific. Mac uses manual activity sessions, Core Location when allowed,
  and IOKit power-source state for charging-only downloads.
- Treat both Wi-Fi and wired Ethernet as unmetered on macOS. Show network/power policy
  state and never let missing activity/device data fail a Sync action silently.
