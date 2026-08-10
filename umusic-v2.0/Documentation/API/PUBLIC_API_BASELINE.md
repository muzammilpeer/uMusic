# UMusicCore Public API Baseline

Version: `2.0.0-alpha.19` (Beta 1 freeze candidate)

The compatibility surface began in Sprint 1 and is frozen for Beta 1 after Sprint 19 validation. It consists of:

- `UMusicClient`, authentication, and six media/library capability protocols.
- Immutable Sendable snapshots and track/playlist value summaries.
- `DefaultUMusicClient` dependency-injected composition container.
- `UMusicCompositionRoot.makePlaceholderClient()` for shell integration only.
- `UMusicCoreVersion` and the bundled resource manifest.

Infrastructure implementation types, Apple player objects, managed objects, Keychain APIs, SwiftUI views, and model tensors are intentionally excluded.

`Scripts/dump-public-api.sh` generates machine-readable symbol graphs when supported by the installed SwiftPM toolchain. CI must diff the accepted graph before a stable framework release.
