# Sprint 1 Report

Status: **Substantially implemented — XCFramework packaging and signed app launch smoke pending**  
Date: 2026-08-09

## Delivered behavior

- Compilable Swift 6 package targeting provisional iOS/iPadOS 17 and macOS 14.
- Static `UMusicCore` and `UMusicImportClient` products, SwiftUI `UMusicPresentation`, and thin `UMusicApp` executable composition.
- Clean module targets for Domain, Support, Data, Networking, Playback, Offline, Context, Learning, Telemetry, Security, and Core.
- Stable capability protocols, immutable Codable/Sendable snapshots, injected `DefaultUMusicClient`, and placeholder composition root.
- Independent extension-safe import URL type with scheme/length policy.
- Four-tab SwiftUI shell: Home, Library, Now, Search; independent typed navigation paths and placeholder states.
- Theme tokens, versioned framework resource manifest, and initial privacy manifest.
- Deterministic date/UUID/random test seams and structured sensitive-field redaction.
- Automated source dependency, extension import, and public-facade leakage checks.
- Generated public API identifier baselines for Core, Domain, and ImportClient with CI diff script.
- Focused GitHub Actions workflow and one-command Sprint 1 validation script.

## Architecture decisions

- Presentation imports `UMusicCore`, not infrastructure modules.
- The public facade exposes no AVPlayer, Core Data, Keychain, SwiftUI, or model tensor implementation type.
- Framework-backed mutable services will remain actor-owned; placeholders already expose AsyncStream snapshots.
- AVFoundation-facing APIs remain explicitly main-actor isolated based on P-001 evidence.
- The share extension will link `UMusicImportClient` only.

## Tests and validation

```sh
CLANG_MODULE_CACHE_PATH=/tmp/umusic-v2-clang-cache SWIFT_MODULE_CACHE_PATH=/tmp/umusic-v2-swift-cache swift test --disable-sandbox --package-path umusic-v2.0 --scratch-path /tmp/umusic-v2-sprint1-swift-build
xcodebuild -quiet -scheme UMusicCore -destination 'generic/platform=iOS' -derivedDataPath /tmp/umusic-v2-sprint1-core-ios CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -scheme UMusicPresentation -destination 'generic/platform=iOS' -derivedDataPath /tmp/umusic-v2-sprint1-ui-ios CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -scheme UMusicPresentation -destination 'generic/platform=macOS' -derivedDataPath /tmp/umusic-v2-sprint1-ui-macos CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -scheme UMusicApp -destination 'generic/platform=iOS' -derivedDataPath /tmp/umusic-v2-sprint1-app-ios CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -scheme UMusicApp -destination 'generic/platform=macOS' -derivedDataPath /tmp/umusic-v2-sprint1-app-macos CODE_SIGNING_ALLOWED=NO build
umusic-v2.0/Scripts/validate-architecture.sh
umusic-v2.0/Scripts/check-public-api.sh
```

- 11 Swift tests passed.
- Generic iOS Core, Presentation, and App builds passed.
- Generic macOS Presentation and App builds passed.
- Three architecture enforcement tests passed.
- API baseline comparison passed.
- `UMusicCore` iOS archive command passed, but generated Swift-package scheme installed object files instead of a distributable framework.

## Known limitations

- No real authentication, network, persistence, playback, or sensor behavior was added; those belong to later sprints.
- The app entry compiles through SwiftPM but is not yet a signed `.xcodeproj` application with capabilities.
- A device/simulator/macOS `UMusicCore.xcframework` has not been honestly produced; see `Documentation/FRAMEWORK_INTEGRATION.md`.
- A physical signed-app launch smoke test has not run.
- SwiftPM prints sandbox/cache warnings in the restricted development environment; validation scripts use isolated `/tmp` caches and disable SwiftPM's nested sandbox.

## Privacy impact

No data is collected. The privacy manifest declares no tracking or collected-data APIs for the scaffold. Import requests validate only URL structure and are not transmitted.

## Sprint gate assessment

- Package/modules/facade/test seams/navigation/theme/resources/CI: pass.
- Swift tests and generic platform compilation: pass.
- API baseline: pass.
- Packaged XCFramework and clean host/extension integration: pending.
- Signed launch smoke: pending.

Sprint 1 should remain open until the two pending packaging/runtime gates are completed. Sprint 2 protocol work may begin against the stable package facade without changing these decisions.

