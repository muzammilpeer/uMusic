# P-001 Playback Restoration Report

- Status: **Partial pass — deterministic contract and platform compile pass; physical audio measurement pending**
- Date: 2026-08-09
- Host: Apple Silicon macOS, Swift 6.3.3, Xcode 26.6
- Target baseline: iOS 17 / macOS 14

## Implemented

- Codable track, position, and queue snapshot.
- Synchronous snapshot publication during `PlaybackRestorer` initialization.
- Explicit restoration states: empty, snapshot, preparing, ready, playing, and recoverable failure.
- Deferred Play intent while media preparation is in flight.
- Main-actor-isolated AVPlayer adapter that checks file availability, loads playability, seeks, and remains paused.
- Controlled-player tests for deterministic launch/play/failure behavior.

## Results

| Check | Result |
|---|---|
| 100 restored launches remain paused | Pass in controlled test |
| Snapshot publication under 300 ms | Pass; all controlled iterations completed within the 1 ms test run resolution |
| Early Play honored after preparation | Pass |
| Seek intent within 500 ms | Pass in controlled adapter; real AVPlayer/device measurement pending |
| Missing local file recoverable | Pass in controlled test and implemented in AVPlayer adapter |
| Generic iOS compile | Pass |
| Real audible-output/autoplay validation | Pending physical-device spike |

## Commands

```sh
swift test --package-path umusic-v2.0/Prototypes/P-001-PlaybackRestore
xcodebuild -quiet -scheme PlaybackRestoreProbe -destination 'generic/platform=iOS' -derivedDataPath /tmp/umusic-v2-p001-ios CODE_SIGNING_ALLOWED=NO build
```

Swift tests: 3 tests passed. The iOS build produced an arm64 iOS object and Swift module.

## Finding

Swift 6 initially rejected a nonisolated `PlayerPreparing` protocol implemented by a main-actor AVPlayer class. The protocol was correctly made `@MainActor`; concurrency checks were not suppressed. Production playback APIs that directly wrap AVFoundation should retain this explicit actor boundary, while policy/state above the adapter remains actor-owned.

## Remaining pass work

- Use a real MP3 fixture on the nominated minimum iPhone.
- Run 100 launches while detecting any audio before explicit Play.
- Measure UI snapshot latency, asset readiness, seek accuracy, early Play, interruptions, and main-thread stalls.
- Test remote preparation under a controlled network profile.

No credentials, user media, or personal history were used.

