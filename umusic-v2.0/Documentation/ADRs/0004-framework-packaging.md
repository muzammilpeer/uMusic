# ADR 0004: Framework and Extension Packaging

- Status: Provisional pending P-002
- Date: 2026-08-09

## Decision

Build a static `UMusicCore.xcframework` for iOS device/simulator and macOS, plus a smaller extension-safe `UMusicImportClient` product. The app owns SwiftUI presentation and composition.

## Consequences

Public APIs use Sendable values/protocols/streams and semantic versioning. Core Data, AVFoundation objects, SwiftUI views, Keychain implementation, and model tensors remain internal. Resource lookup and symbol boundaries must pass P-002 before acceptance.

