# Sprint 10 report — SwiftUI Apple client and online playback

## Delivered

- Swift 5 SwiftUI application for iPhone, iPad, and native macOS from one target.
- Testable API, credential, queue, event, and audio boundaries.
- HTTPS onboarding and hashed backend device registration.
- device token stored in Keychain with sign-out and revoked-token handling.
- Paginated library/search API plus track, artist, album, and playlist browsing.
- AVPlayer service, persistent queue, mini-player, Now Playing screen, seeking,
  next/previous, interruption handling, and headphone-route pause.
- iOS background-audio declaration and playback audio-session category.
- Lock Screen, Control Center, headphone remote commands, and Now Playing metadata.
- 15-second listening progress events, stable client UUIDs, disk-backed retry queue,
  and remove-after-server-acknowledgement reconciliation.
- Authenticated web device portal for immediate token revocation.

## Verification

- iOS Simulator generic build passes for both iPhone and iPad families.
- Native macOS generic build passes.
- Swift core tests pass for frozen JSON decoding, queue restoration, and event acknowledgement.
- 80 Django tests pass; coverage meets the 85% gate.
- Ruff, strict mypy, and migration consistency checks pass.

## Remaining physical-device gate

Automated builds cannot prove that audio continues with a real iPhone locked. Before
Sprint 10 is considered field-verified, install the signed app on an iPhone and test:

1. Start a track, lock the screen, and listen through a transition to the next track.
2. Use Lock Screen/Control Center and wired or Bluetooth headphone commands.
3. Disconnect/reconnect headphones and accept an interruption such as a call.
4. Revoke the device at `/library/devices/` and confirm the next API refresh signs out.
5. Confirm listening events appear in backend listening history exactly once.

Sprint 11 offline manifests can begin after this short physical smoke test, or proceed
with the gate explicitly recorded as pending.
