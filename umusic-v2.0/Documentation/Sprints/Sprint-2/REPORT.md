# Sprint 2 Report

Status: **Implemented and locally validated on client and backend; signed-device UI run pending**
Date: 2026-08-09

## Delivered behavior

- Strict server URL normalization: HTTPS by default, implicit HTTPS for host-only input, no URL credentials/query/fragment, and explicit HTTP exception for localhost development only.
- Pre-authentication bootstrap negotiation for API version and required `catalog_sync`/`audio_stream` capabilities.
- URLSession session creation and refresh-rotation requests using default Apple TLS validation; no custom trust bypass exists.
- Actor-owned authentication states for signed out, server validation, authentication, authenticated, offline, expired, revoked, and redacted failures.
- One shared refresh task for concurrent access-token callers.
- Keychain token persistence using `AfterFirstUnlockThisDeviceOnly`; passwords are never persisted.
- Non-secret server configuration persistence in UserDefaults so Keep Me Signed In can restore a session.
- Restore flow that refreshes expired persisted tokens and routes authenticated users into the app shell.
- Revoked or unauthorized refresh clears persisted tokens.
- Explicit logout choices for keeping data, removing offline media, removing learning history, or removing all device data; the coordinator delegates cleanup to an injected capability.
- Onboarding UI with server URL, username, secure password field, Keep Me Signed In, localhost development option, progress, redacted errors, and request ID.
- Live app composition using URLSession, Keychain, UserDefaults configuration, and a stable non-sensitive installation ID.
- Django `/api/v2/bootstrap`, session creation, refresh rotation, logout/revocation, hashed device-token storage, expiry checks, request IDs, and scoped throttling.
- Refresh-token replay revokes the affected device and its active token family while preserving the existing v1 authentication route.

## Security and privacy

- Password exists only in the SwiftUI secure field and ephemeral request encoding; the view clears it when submission begins.
- Tokens are never stored in Core Data/UserDefaults or included in logs/errors.
- Server URLs containing embedded credentials or token-like query data are rejected.
- Failure UI receives stable codes, generic messages, retryability, and request ID—not response bodies, headers, endpoints, usernames, or tokens.
- Default URLSession certificate validation remains intact.
- No library sync is triggered by authentication.

## Validation

```sh
CLANG_MODULE_CACHE_PATH=/tmp/umusic-v2-clang-cache SWIFT_MODULE_CACHE_PATH=/tmp/umusic-v2-swift-cache swift test --disable-sandbox --package-path umusic-v2.0 --scratch-path /tmp/umusic-v2-sprint2-swift-build
xcodebuild -quiet -scheme UMusicApp -destination 'generic/platform=iOS' -derivedDataPath /tmp/umusic-v2-sprint2-app-ios CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -scheme UMusicApp -destination 'generic/platform=macOS' -derivedDataPath /tmp/umusic-v2-sprint2-app-macos CODE_SIGNING_ALLOWED=NO build
umusic-v2.0/Scripts/dump-public-api.sh
umusic-v2.0/Scripts/check-public-api.sh
```

- 20 Swift tests passed after the final UI/account wiring.
- Authentication coverage includes URL validation, success/persistence, restoration, cancellation, capability mismatch, 12-way refresh concurrency, denied secure storage, logout disposition, offline error redaction, architecture boundaries, and existing Sprint 1 behavior.
- Generic iOS and macOS app builds passed.
- 12 account/backend tests passed; Django system checks, Ruff, MyPy, and migration drift checks passed.

## Schema/API changes

- Public API version advanced to `2.0.0-alpha.2`.
- `UMusicClient` now exposes `AuthenticationManaging`.
- API contract documents pre-auth bootstrap and `/api/v2/auth/session/refresh`.
- No Core Data schema exists or changed in this sprint.

## Known limitations

- Docker image validation could not finish because registry metadata timed out; isolated Django validation completed successfully without changing services or volumes.
- Keychain behavior compiled but was not exercised in a signed app with the final access group.
- Logout data removal uses an injected no-op until Offline/Telemetry stores exist; the selected disposition is correctly forwarded and tested.
- The remaining Sprint 1 XCFramework and signed-host gates are unchanged.

## Recommended next sprint

Proceed to Sprint 3 catalog persistence and deliberate sync after deciding whether the current backend will implement the documented `/api/v2` contract directly or expose a compatibility adapter.
