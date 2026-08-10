# Sprint 17 Report

Status: **Adaptive iPad/macOS navigation, per-window route restoration, keyboard commands, search focus, and accessibility-oriented layout updates implemented and compile-validated; signed-device accessibility/localization and platform-adapter audits remain release gates**

Date: 2026-08-10

## Delivered behavior

- The same typed `AppNavigationModel` now drives two layouts: compact iPhone uses the established four tabs, while regular-width iPad and macOS use a balanced `NavigationSplitView` sidebar/detail layout.
- Home, Library, Now, and Search retain their independent typed navigation stacks in both layouts. Deep links continue to select the same route identity rather than entering a platform-specific duplicate route.
- Scene restoration serializes the selected destination, all four typed route stacks, and search query. Restore input is bounded to 64 KiB, 32 routes per stack, and 512 search characters before it can affect navigation.
- `@SceneStorage` keeps restoration state scoped to each app scene/window instead of using one global navigation record.
- Added focused-scene command routing. Command-1, Command-2, and Command-3 open Home, Library, and Now Playing; Command-F opens Search and presents keyboard focus; Space invokes Play/Pause through the active scene.
- macOS adds an Option-Command-I menu handoff that opens an installed sibling or `/Applications/UMusicDataInspector.app` without attempting to mutate a live store.
- The mini player remains an outer safe-area inset shared by compact and split layouts, keeping final list/form rows reachable.
- Now Playing no longer applies a fixed point-size font to the primary transport control. Titles and artists support multiline semantic text, and the transport cluster is grouped for assistive navigation.
- Existing Reduce Motion behavior remains authoritative for Home and the visualizer. Layout uses semantic SwiftUI alignment and native symbols without forcing left-to-right direction.
- iOS-only motion and workout controls remain compile-time excluded from macOS. The macOS audio-route provider now returns `unknown` instead of inventing a built-in-speaker route.
- Added a code-review accessibility/platform audit covering VoiceOver labels, Voice Control names, Dynamic Type, keyboard navigation, focus, contrast, Reduce Motion, right-to-left layout, empty/error states, and remaining manual gates.
- Framework version advanced to `2.0.0-alpha.17`; resource metadata and public API baselines were refreshed.

## Validation

- All 113 Swift tests pass, including new typed-restoration bounds, adaptive-shell/sidebar contract, keyboard command/focus contract, semantic right-to-left layout contract, and non-fabricated macOS audio-route coverage.
- Generic iOS and macOS `UMusicApp` builds pass with code signing disabled.
- The macOS `UMusicDataInspector` product builds successfully.
- Architecture rules and public production symbol-graph baselines pass. SwiftPM continues to emit the known test-bundle extraction warning after validating production modules.
- `git diff --check` passes.

## Boundaries and remaining gates

- Generic iOS compilation covers the shared iPhone/iPad code path, but this sprint did not run a signed iPad build through every Split View size, Stage Manager, rotation, or external-display configuration.
- Source and automated contract checks do not replace manual VoiceOver, Voice Control, Full Keyboard Access, Switch Control, accessibility-size Dynamic Type, contrast, and right-to-left testing. The checklist is in `Documentation/Accessibility/SPRINT17_AUDIT.md`.
- No translated localization catalog ships yet. User-visible SwiftUI literals participate in the localization system, but translation, pluralization review, long-string screenshots, and linguistic QA remain release blockers for a multilingual release.
- The inspector menu handoff works only when a signed `UMusicDataInspector.app` is installed beside uMusic or in `/Applications`. Failure feedback and a registered document/URL handoff are not yet implemented.
- Scene restoration is locally round-tripped and bounded, but simultaneous multiwindow close/reopen behavior has not been exercised in a signed app.
- macOS no longer fabricates audio-route data, but it does not yet expose a real macOS output-route classifier. The live composition still uses an unavailable coarse-place adapter, and a charging-only download policy backed by IOKit has not been implemented. Unsupported values remain unavailable/unknown rather than synthetic.
- macOS network classification uses `NWPath`: satisfied, non-expensive wired Ethernet and Wi-Fi are treated as unmetered. Hardware-level network/power behavior still requires device validation.
- No backend source, database migration, Docker image, or production service was changed or deployed for Sprint 17.

## Next sprint entry

Sprint 18 should profile minimum-device performance and complete security/privacy hardening, then design and test the copy-first, non-destructive v1-to-v2 migration adapter with checkpoints and rollback limited to incomplete v2 imports.
