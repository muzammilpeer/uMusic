# uMusic for Apple platforms

One SwiftUI target supports iPhone, iPad, and native macOS in Swift 5 language mode.

## Open and run

1. Open `UMusic.xcodeproj` in Xcode.
2. Select the `UMusic` scheme and an iPhone, iPad, or My Mac destination.
3. Select your development team and use your own bundle identifier if required.
   Enable the HealthKit capability for that identifier if Health workout creation
   will be used. Enable Keychain Sharing for the app and Share Extension identifiers;
   keep their access group aligned if the team or bundle IDs change. Location remains
   optional and manual context works when denied.
4. Run the app. It defaults to `https://umusic.muzammilpeer.uk/`; the field remains
   editable for recovery or another deployment.
5. Sign in with the uMusic owner account. The issued device token is stored in
   Keychain and can be revoked from `/library/devices/`.

For local simulator development, HTTPS is recommended. The production app should not
weaken App Transport Security to accommodate a cleartext origin.

## Verification

```bash
swift test
xcodebuild -project UMusic.xcodeproj -scheme UMusic \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project UMusic.xcodeproj -scheme UMusic \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Physical-device verification is required for background playback while locked,
headphone route changes, Control Center commands, and real network transitions.

## Platform parity

The shared SwiftUI app provides library/search, playlists, manual Sync, online and
offline playback, queue/seek restoration, storage quotas, per-track downloads/deletion,
URL imports, activity sessions, place context, Now Playing, and admin tools on iPhone,
iPad, and macOS. Both iOS and macOS embed the compact **Import to uMusic** Share
Extension for YouTube URLs.

HealthKit and Core Motion activity classification are iPhone/iPad capabilities. macOS
uses manual activity selection and a uMusic session timer, and does not display inactive
Health or motion controls. The Mac download policy reads Wi-Fi and AC/battery state.

## Workout privacy

Workout mode uses a battery-conscious one-shot location request to resolve places
that were explicitly marked for location matching. Raw coordinates are not retained
unless **Store raw route** is enabled; the local route can be erased from the same
screen. HealthKit access is optional and requested only when starting a session with
**Create Health workout** enabled.
