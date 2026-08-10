# Sprint 15 Report

Status: **Extension-safe remote-import workflow, App Group handoff, shared credential bridge, and owner-scoped backend idempotency implemented and locally compile-validated; signed extension-target and backend runtime validation remain integration gates**  
Date: 2026-08-10

## Delivered behavior

- Expanded `UMusicImportClient` into an extension-safe client that depends only on Foundation, Security, and `UMusicSupport`; it does not link playback, telemetry, location, motion, HealthKit, Core Data, or ML.
- URL policy accepts HTTP/HTTPS input, upgrades HTTP to HTTPS, normalizes host/default ports, removes fragments, rejects embedded credentials and oversized values, and permits only recognized YouTube hosts or direct `.mp3` paths.
- Multiple share representations are inspected deterministically and the first supported URL is selected.
- The minimal share controller displays the normalized URL, provider/legal availability copy, and one **Send to Server** action. It never downloads or plays media.
- App Group handoff persists only the normalized URL, provider classification, and stable idempotency UUID. Duplicate enqueue attempts do not duplicate work.
- The containing app processes pending handoffs on launch/foreground, publishes the current server/token to a separate shared-Keychain credential record, and preserves pending jobs after offline/authentication failures for a later retry.
- Shared credential migration is an explicit copy-once operation and never places credentials in App Group defaults or source.
- `URLSessionImportJobClient` submits authenticated jobs, decodes progress state, resolves job status, maps authentication/provider/offline failures, and produces a containing-app job deep link containing only the opaque job UUID.
- Backend `AdapterJob` now has a nullable owner-scoped idempotency key protected by a conditional database uniqueness constraint and migration.
- Remote-import creation uses transactional `get_or_create`; repeat requests return the original job without creating items or dispatching a second worker task.
- The compatibility API requires `idempotency_key`, accepts the single normalized `url`, returns `202` for new work and `200` for a repeat, and retains the existing authenticated job-status endpoint.
- API documentation and extension entitlement/setup documentation now describe the exact privacy and signing boundary.
- Framework version advanced to `2.0.0-alpha.15`; resource metadata and public symbol baselines were refreshed.

## Validation

- All 106 Swift tests pass.
- Sprint-specific tests cover HTTP normalization, provider classification, URL length, file/script/credential/unsupported URL rejection, multiple representations, duplicate App Group enqueue, persistence across coordinator recreation, shared credential migration, privacy-safe job deep links, and offline retry preservation.
- Generic iOS and macOS `UMusicApp` builds pass with code signing disabled. The separate
  `UMusicShareExtensionUI` product also passes a generic iOS compile check.
- Architecture rules confirm the extension-safe product does not import sensitive Apple or uMusic implementation modules.
- Public production symbol-graph checks pass. SwiftPM continues to emit the known test-bundle extraction warning after validating required production graphs.
- Backend Python source compiles and `git diff --check` passes.

## Boundaries and remaining gates

- This repository currently builds the app through Swift Package Manager and does not yet contain a signed Xcode Share Extension target. The extension UI has a separately compiled Swift package product and its entitlements are implemented, but embedding/signing the extension, configuring both App Group entitlements, and setting the resolved `UMusicSharedKeychainAccessGroup` Info property remain required in the generated/maintained Xcode host project.
- Because the extension target is not embedded, representative share tests from Safari/YouTube and macOS, cancellation behavior under the real extension host, and physical extension memory/time measurements remain unverified.
- Job status models, API polling, and safe deep-link generation exist; a dedicated containing-app import-progress screen/route is not yet presented in the SwiftUI shell.
- The environment has no Django or pytest installation and no running Docker services. Backend runtime tests, migration application/rollback, API authentication probes, and the new exactly-once regression test could not run here. `compileall` passed, but it is not a substitute for those gates.
- Redirect and private-address enforcement remains server-side, where the existing downloader validates the initial HTTPS target and each redirect. The extension does not preflight or follow the media URL.
- The Send action is accompanied by explicit authorization wording and sends `attested: true`; product/legal review of the final localized copy is still required before distribution.
- No Docker image was built or deployed, and no database migration was applied to a live environment.

## Next sprint entry

Sprint 16 should complete export/share-sheet cleanup and privacy-safe diagnostics, then add the optional energy-aware visualizer behind Reduce Motion and Low Energy Mode without coupling it to playback-critical execution.
