# P-002 Framework Resource and Extension Boundary Report

- Status: **Partial pass — package products/resources/platform compile pass; packaged XCFramework integration pending**
- Date: 2026-08-09
- Host: Apple Silicon macOS, Swift 6.3.3, Xcode 26.6
- Target baseline: iOS 17 / macOS 14

## Implemented

- Static `UMusicCoreProbe` product with a versioned JSON model manifest loaded through `Bundle.module`.
- Separate static `UMusicImportClientProbe` with only extension-safe Foundation URL request types.
- Resource decoding and HTTP/HTTPS boundary tests.
- A core-only playback marker used to audit that import source has no playback dependency.

## Results

| Check | Result |
|---|---|
| macOS Swift package compile/tests | Pass; 2 tests |
| Core resource resolves and decodes | Pass |
| Extension request rejects file URL | Pass |
| Generic iOS Core compile | Pass; arm64 module/object and resource bundle produced |
| Generic macOS Import compile | Pass; arm64/x86_64 modules produced |
| Import source forbidden-framework scan | Pass; no AVFoundation, CoreLocation, CoreMotion, HealthKit, or playback marker reference |
| Final XCFramework device/simulator/macOS packaging | Pending |
| Host app and real share-extension integration | Pending |
| Symbol-graph/API baseline | Pending Sprint 1 packaging harness |

## Commands

```sh
swift test --package-path umusic-v2.0/Prototypes/P-002-XCFrameworkResources
xcodebuild -quiet -scheme UMusicCoreProbe -destination 'generic/platform=iOS' -derivedDataPath /tmp/umusic-v2-p002-core-ios CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -scheme UMusicImportClientProbe -destination 'generic/platform=macOS' -derivedDataPath /tmp/umusic-v2-p002-import-macos CODE_SIGNING_ALLOWED=NO build
rg -n 'AVFoundation|CoreLocation|CoreMotion|HealthKit|PlaybackCapabilityMarker' umusic-v2.0/Prototypes/P-002-XCFrameworkResources/Sources/UMusicImportClientProbe
```

Xcode's generated Swift-package schemes returned success but warned that supported-platform metadata was empty. Produced artifacts were inspected directly; this warning is why XCFramework packaging is not marked complete.

## Finding

SwiftPM's resource bundle resolves correctly and the two-source-product boundary is viable. Final static XCFramework packaging needs a dedicated Xcode framework project or repeatable archive harness; object-file output from the generated package scheme alone is insufficient evidence for distribution.

## Remaining pass work

- Create disposable framework/host/extension Xcode targets.
- Archive iOS device, simulator, and macOS slices with distribution interfaces.
- Create and integrate the XCFramework into clean host targets.
- Verify resource hash and import-product exported symbols in every slice.

No production model, credentials, or user data were used.

