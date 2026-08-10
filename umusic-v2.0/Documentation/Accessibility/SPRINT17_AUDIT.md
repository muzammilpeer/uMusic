# Sprint 17 accessibility and platform audit

Date: 2026-08-10

## Code-reviewed contracts

- Compact iPhone uses four primary tabs; regular-width iPad and macOS use a sidebar and detail column backed by the same typed routes.
- Navigation state is restored per scene with a 64 KiB decode limit, 32-route limit per stack, and 512-character search limit.
- Search is keyboard-focusable from Command-F. Command-1/2/3 switches Home, Library, and Now Playing; Space invokes Play/Pause through the focused scene.
- Controls use visible or accessibility labels. Player transport controls expose their text labels even when rendered icon-only.
- Semantic text styles are used for user-visible text. The remaining fixed dimensions are decorative artwork/layout bounds, not text sizes.
- Search and text-entry scroll surfaces use interactive keyboard dismissal.
- The mini player remains a safe-area inset outside both compact and split navigation, so final content remains reachable.
- Reduce Motion stops Home animation and the visualizer timeline. Native SwiftUI stacks, alignment, and SF Symbols are used without forcing layout direction, preserving right-to-left mirroring.
- macOS source excludes motion sampling and workout controls at compile time. Manual activity, network classification, and supported coarse-location controls remain visible; unavailable sources stay unavailable rather than producing synthetic data.
- macOS receives app menu keyboard commands and a handoff command for an installed `UMusicDataInspector.app`.

## Manual release gates

These require signed builds and supported physical devices and are not replaced by source tests:

- VoiceOver rotor/order and Voice Control name activation on iPhone and iPad.
- Dynamic Type through accessibility sizes, including landscape and Split View.
- Contrast review for every theme/accent combination using Accessibility Inspector.
- Keyboard-only focus order and Full Keyboard Access on iPad; VoiceOver and keyboard navigation on macOS.
- Right-to-left screenshots with a real localized build and long translated strings.
- Multiple-window restoration and document/inspector handoff with installed signed apps.
- Empty, offline, permission-denied, and error-state review on the minimum supported OS versions.

No non-English localization catalog ships yet. SwiftUI localization keys and semantic layout are prepared, but translated copy and linguistic review remain a release gate.
