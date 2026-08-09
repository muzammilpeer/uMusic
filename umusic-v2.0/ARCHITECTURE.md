# Technical Architecture

## Repository shape

```text
umusic-v2.0/
├── Package.swift                         # development/test composition
├── Sources/
│   ├── UMusicCore/                       # public facade and stable value types
│   ├── Domain/                           # entities, policies, use cases, protocols
│   ├── Data/                             # Core Data, repositories, migrations
│   ├── Networking/                       # auth, API, sync, transfer
│   ├── Playback/                         # audio engine, queue, restoration
│   ├── Offline/                          # quota, download, integrity, eviction
│   ├── Context/                          # time, route, motion, location, HealthKit adapters
│   ├── Learning/                         # features, ranking, aggregation, model runtime
│   ├── Telemetry/                        # local events, batching, retention, export
│   ├── Security/                         # Keychain and data-protection adapters
│   └── Support/                          # clock, IDs, logging, test seams
├── Apps/UMusicApp/
│   ├── App/
│   ├── Navigation/
│   ├── Screens/{Home,Library,Now,Search,Settings,Onboarding}/
│   ├── Components/
│   ├── ViewModels/
│   ├── Theme/
│   ├── Resources/
│   └── Extensions/UMusicShareExtension/
├── Tests/{Unit,Integration,Contract,Performance,Energy,UITests}/
├── Tools/{ModelBuilder,DataInspector,SchemaValidator}/
└── Documentation/
```

Do not create classes named `ViewController` for SwiftUI screens. The share extension may use an Apple-required host controller, but application presentation remains `View` + observable state/view model.

## Clean architecture boundaries

- **Presentation** imports `UMusicCore` public API and UI support only.
- **Domain** contains no SwiftUI, Core Data, URLSession, AVFoundation, HealthKit, Core Location, or Core ML imports.
- **Infrastructure/Data** implements domain protocols.
- **UMusicCore** is the composition facade exposed through the XCFramework.
- Dependencies point inward. Implementations are injected by a composition root.

Example public surface:

```swift
public protocol UMusicClient: Sendable {
    var playback: any PlaybackControlling { get }
    var library: any LibraryProviding { get }
    var playlists: any PlaylistManaging { get }
    var personalization: any PersonalizationManaging { get }
    var offline: any OfflineManaging { get }
    var diagnostics: any DiagnosticsProviding { get }
}
```

Expose immutable `Sendable` snapshots and `AsyncSequence` state streams. Do not expose Core Data objects, AVPlayer, managed object contexts, Keychain types, or internal model tensors across the framework boundary.

## XCFramework strategy

- Build `UMusicCore.xcframework` for iOS device/simulator and macOS; include arm64 and simulator slices as appropriate.
- Keep extension-safe APIs in a separate `UMusicImportClient` product so the extension cannot accidentally link unavailable playback/sensor code.
- Version public API semantically and generate symbol-graph/API-diff checks in CI.
- Resources/models ship in an explicit bundle located through `Bundle.module` internally.
- Prefer static linkage unless runtime model/resource constraints require dynamic linkage.
- Provide privacy manifest and required-reason API declarations.

## Runtime components

### PlaybackCoordinator actor

Owns queue intent, snapshot persistence, and transitions. An `@MainActor` adapter performs AVFoundation/MediaPlayer calls that require main-thread access. The player publishes small immutable snapshots instead of high-frequency time updates to the entire UI.

### LibrarySync actor

Fetches cursor pages, validates schema, writes to a background Core Data context, merges changes, and atomically advances the sync cursor. Cancellation leaves the prior cursor valid.

### DownloadCoordinator actor

Maps background URLSession task IDs to track/revision, restores tasks after launch, verifies checksum, commits files atomically, and asks `QuotaManager` for eviction candidates.

### ContextCollector actor

Starts only during an active listening session when the corresponding preference and permission permit it. It converts raw platform callbacks to coarse context, applies confidence/TTL, and disposes raw samples promptly.

### EventRecorder actor

Receives semantic events, coalesces position/heartbeat information, and saves batches. A crash-safe session checkpoint is written on meaningful transitions and at a bounded heartbeat.

### RecommendationEngine actor

Builds candidates, extracts local features, invokes a small Core ML ranker when available, applies policy constraints, creates reason codes, and falls back to deterministic heuristics on error.

## Concurrency rules

- `@MainActor`: SwiftUI state mutation and explicitly required Apple media UI calls.
- Actors: mutable playback, sync, downloads, telemetry, context, and recommendation state.
- Background Core Data contexts perform imports/aggregation/export; merge by persistent history or explicit object IDs.
- CPU-heavy feature extraction/inference runs in detached utility-priority work only through a bounded executor; never one task per track.
- All long operations accept cancellation and report progress.
- UI consumes throttled snapshots. The scrubber may use a local display timer while playing rather than database/player-wide writes.
- No blocking network, file, model, JSON, image decode, or database work on the main actor.

## Playback state machine

```text
idle → preparing → ready/paused → playing ↔ paused
                    │              │
                    └→ failed ← buffering/interrupted

launch restore: persisted snapshot → ready/paused (never auto-play)
manual next: finalize observation → select queue head → preparing
```

Persist on track change, manual seek, pause/resume, queue mutation, 15-second crash checkpoint, and scene background. Listening telemetry remains coarser and is flushed at 120 seconds in Low Energy Mode or immediately at pause/completion.

## Persistence stores

- `Catalog.sqlite`: server-owned library and playlist mirror.
- `User.sqlite`: queue, sessions, observations, learned affinities, settings references, and model registry.
- `Telemetry.sqlite`: append/aggregate-oriented events with aggressive retention and export support.
- Binary audio/artwork lives outside SQLite under versioned directories with manifest/checksum records.
- Keychain holds tokens/credentials; UserDefaults holds non-sensitive launch preferences only.

Separate stores make catalog replacement, telemetry expiration, and user export safer. Use WAL, appropriate indexes, batch inserts/deletes, and periodic checkpoint/maintenance only while idle and powered.

## Dependency and test strategy

- Protocol adapters for clock, random source, network path, battery/energy policy, location, motion, HealthKit, audio route, Keychain, and model runtime.
- Unit tests for policies/state machines; integration tests for Core Data and background URLSession; contract tests against API fixtures; UI tests for navigation and permission denial.
- Deterministic recommendation fixtures assert queue constraints and explanations.
- Instruments/XCTest metrics cover launch, scroll, memory, energy, database, download, inference, and audio underruns.
