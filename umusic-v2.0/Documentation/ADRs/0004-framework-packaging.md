# ADR 0004: Framework and Extension Packaging

- Status: Provisional; SwiftPM boundary passed, packaged XCFramework pending
- Date: 2026-08-09

## Decision

Build a static `UMusicCore.xcframework` for iOS device/simulator and macOS, plus a smaller extension-safe `UMusicImportClient` product. The app owns SwiftUI presentation and composition.

## Consequences

Public APIs use Sendable values/protocols/streams and semantic versioning. Core Data, AVFoundation objects, SwiftUI views, Keychain implementation, and model tensors remain internal. P-002 verified SwiftPM resource lookup, separate static products, generic iOS/macOS compilation, and a clean import source boundary. This ADR remains provisional until real device/simulator/macOS XCFramework slices integrate into clean host and extension targets.
