# Sprint 18 Security and Privacy Audit

Date: 2026-08-10

## Verified locally

- The bundled privacy manifest declares no tracking and includes the required-reason API categories used by v2: User Defaults (`CA92.1`, `1C8F.1`), disk space (`E174.1`), and file timestamps (`C617.1`). An automated test parses and pins these declarations.
- The catalog SQLite store requests WAL, `NORMAL` synchronous behavior, indexed common predicates, batched fetches, and Complete Until First User Authentication file protection on iOS-family hosts.
- Authentication persistence stores tokens in Keychain and not passwords. Sensitive log fields and sanitized exports have automated denylist coverage.
- Server URL policy requires HTTPS except explicit local-development hosts. Runtime transport uses system URL loading and trust evaluation; certificate pinning is not implemented.
- Export writers use protected files, atomic commits, bounded paths, and explicit cleanup. Tests cover cancellation, disk-full behavior, and traversal-resistant deletion scope.
- Migration outputs use fixed names, protected atomic writes, SHA-256 integrity, checkpoints, and a non-destructive source boundary.
- SwiftPM declares no third-party package dependencies.

## Release gates still open

- The containing signed app must be archived and its merged privacy report inspected. The framework's `NSPrivacyCollectedDataTypes` is empty; product/legal must confirm the final declaration against shipped server behavior and App Store policy.
- Validate Keychain access groups, App Group identifiers, entitlements, and file protection on signed iPhone, share-extension, and macOS builds. Source-level configuration is not signed-capability evidence.
- Capture TLS failure drills for expired, wrong-host, and untrusted certificates against staging. Decide and document whether the private-server threat model needs pinning.
- Run platform dependency/vulnerability scanners for the pinned backend Python image and final Apple archive. Absence of SwiftPM dependencies is not a full supply-chain audit.
- Verify exported temporary files are removed after share-sheet success, cancellation, app termination, and reboot on a physical device.
- Complete a privacy/legal review for activity, coarse-place, listening-history, calendar, HealthKit-derived, and religious-preference processing before distribution.

No security or privacy target was relaxed to close Sprint 18.
