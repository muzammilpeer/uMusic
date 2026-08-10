# Framework and App Integration

## Current Sprint 1 composition

- `UMusicCore`: static product containing the public facade and internal capability modules.
- `UMusicImportClient`: independent static product safe for the future share extension.
- `UMusicPresentation`: SwiftUI navigation shell importing only `UMusicCore` plus UI system modules.
- `UMusicApp`: thin SwiftPM executable entry point used to compile the app composition on iOS and macOS.

Open `Package.swift` in Xcode to inspect or run the package schemes. Production signing, App Groups, background audio, Keychain groups, and the share extension target are intentionally not configured before their owning sprints.

## XCFramework status

The Swift package successfully produces static libraries during `swift test`, and its schemes compile/archive for iOS and macOS. However, Xcode's generated package archive installs `.o` files under `Products/Users/.../Objects` rather than an installable `.framework`. Therefore a valid distributable `UMusicCore.xcframework` is not yet emitted.

Sprint 1 must not treat a collection of object files as a Swift XCFramework. The remaining packaging task is to add a dedicated framework Xcode target/archive harness that:

1. Archives iOS device, iOS simulator, and macOS frameworks with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`.
2. Includes Swift modules/interfaces and the `UMusicCore_UMusicCore.bundle` resources.
3. Runs `xcodebuild -create-xcframework` over verified archives.
4. Integrates the result into clean iOS/macOS host targets.
5. Verifies the separate extension target links `UMusicImportClient` only.

Until then, local development and tests should depend on the Swift package products directly.

