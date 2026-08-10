# Sprint 16 Report

Status: **Export review/cleanup, privacy-safe diagnostics, and an optional energy-aware visualizer implemented and locally validated; physical-device performance and native share-completion instrumentation remain release gates**

Date: 2026-08-10

## Delivered behavior

- Export preparation continues to use the Sprint 13 streaming package writer, bounded per-record encoding, cancellation checks, protected files, low-disk preflight, and partial-package cleanup.
- Added exact package discard that accepts only `.umusicresearch` children of the protected export root and cannot delete an arbitrary caller-provided path.
- Preparing a replacement export discards the previous temporary package. Closing the export review, cancelling it, leaving Learning & Privacy, or completing the review flow discards the prepared package.
- Sharing now opens a dedicated review sheet. Sanitized exports repeat their exclusion guarantees; Full exports repeat event/observation counts and explicitly name track metadata, complete listening timeline, and coarse activity/context at action time.
- Added typed diagnostics with framework, build, data-schema, model, and feature-schema versions.
- Diagnostic issues use normalized stable codes and a metadata allowlist boundary. Sensitive keys and values resembling URLs, absolute paths, credentials, coordinates, usernames, or raw Health data are dropped before presentation.
- The live diagnostics provider reports the uninstalled model as `MODEL_NOT_INSTALLED` with heuristic fallback rather than presenting it as a fault in playback.
- Added an optional Now-screen visualizer derived only from playback position and deterministic animation phases. It does not use a microphone, audio recorder, `AVAudioEngine`, player tap, or media decoding.
- Visualizer rendering is capped at 15 fps normally and 4 fps in uMusic Low Energy Mode. Reduce Motion, paused playback, inactive scenes, and offscreen removal stop periodic rendering and show a static decorative state.
- The visualizer listens to live context settings while visible; leaving the Now hierarchy cancels the SwiftUI task and releases its timeline/rendering state.
- Framework version advanced to `2.0.0-alpha.16`; resource metadata and public API baselines were refreshed.

## Validation

- All 110 Swift tests pass, including the existing 20,000-observation streaming-export fixture. The performance suite was run in isolation after a deliberately concurrent validation run caused host contention.
- New tests cover exact export cleanup and traversal containment, diagnostic key/value redaction, stable local version display, visualizer normal/Low Energy frame budgets, Reduce Motion, background suspension, bounded bar values, and source-level microphone/audio-engine isolation.
- Generic iOS and macOS `UMusicApp` builds pass with code signing disabled.
- Architecture and public production symbol-graph checks pass. SwiftPM continues to emit the known test-bundle graph warning after validating production modules.
- `git diff --check` passes.

## Boundaries and remaining gates

- SwiftUI `ShareLink` does not expose the system activity controller's completion callback. The package is deleted when the in-app review closes or its parent disappears, covering user completion/cancellation of the review, but it may remain temporarily while the review sheet stays open after the system share UI returns. A native platform share presenter is required for immediate callback-level cleanup.
- The current export is a protected directory package, not an encrypted ZIP. Encryption remains optional and no key-management policy has been approved.
- The visualizer is intentionally decorative and position-derived; it is not a frequency spectrum or waveform analysis of the MP3. Adding real audio analysis would require a separately measured, non-playback-critical data path.
- No physical-device Instruments run was performed. CPU/GPU/energy budgets, memory during a 1 GB export, thermal behavior, frame pacing, route-change stress, and proof of zero audio underruns remain release gates.
- The automated large-export fixture contains 20,000 observations rather than 1 GB of source telemetry and therefore does not prove the final peak-memory target.
- Diagnostics currently surface static version state and the model fallback code. A broader catalog of runtime failures can be added only through typed, redacted issue producers; raw errors must never be forwarded directly.
- No backend source, database migration, Docker image, or production service was changed or deployed for Sprint 16.

## Next sprint entry

Sprint 17 should adapt the established routes for iPad and macOS, add keyboard/window behavior, and complete accessibility/localization audits while hiding unsupported Apple capabilities on each platform.
