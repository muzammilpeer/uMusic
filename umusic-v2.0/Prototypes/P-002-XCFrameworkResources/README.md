# P-002 XCFramework Resource and Boundary Probe

Disposable Swift package with two static products:

- `UMusicCoreProbe` owns a versioned bundled model manifest and a playback-only marker.
- `UMusicImportClientProbe` contains only extension-safe URL request value types.

Run:

```sh
swift test --package-path umusic-v2.0/Prototypes/P-002-XCFrameworkResources
```

SwiftPM resource lookup and source/symbol separation are verified here. Building and integrating final device/simulator/macOS XCFramework slices remains a separate P-002 measurement before the ADR becomes Accepted.

