# Sprint 12 report — workout and place intelligence

## Delivered

- Glanceable workout UI with large playback controls for cycling, running, gym,
  walking, focus, relaxation, backend-defined presets, and user-created custom
  activities.
- Manual place selection always remains available.
- Optional Core Location one-shot matching against owner-controlled geofences;
  denial or no match falls back to manual context.
- Raw coordinates are not retained by default. Explicit route opt-in stores data
  only in the app's local application-support directory and includes an erase action.
- Optional HealthKit authorization and workout creation on iPhone, with HealthKit
  entitlement and purpose strings. The macOS target uses the manual workout flow.
- Timed warm-up, sustain, recovery, rest, steady, and cooldown phases based on the
  backend activity curve.
- Each phase transition creates a new immutable backend context snapshot and attaches
  that snapshot to subsequent listening events for learning.
- Bounded on-device reranking changes only the next eight tracks. Played tracks and
  the current track retain their positions, so context changes never interrupt audio.
- Battery/privacy diagnostics show Low Power Mode, location state, Health workout
  state, and route-retention controls.
- Sprint 11 prepared queues remain local-first and require no network for playback.

## Verification

- 81 Django tests pass.
- Ruff and strict mypy pass across 125 Python source files.
- 5 Swift core tests pass, including exact workout phase boundaries and preservation
  of the current/past queue during energy reranking.
- Generic iOS Simulator build passes for the shared iPhone/iPad target.
- Generic native macOS build passes.
- Swift language mode remains explicitly Swift 5.

## Deferred final-sprint field matrix

Per project direction, physical and adverse-condition testing remains deferred to
the final sprint. It must cover a locked-screen outdoor cycling/running session,
airplane-mode prepared playback, location denial, real geofence matching, HealthKit
authorization/save, phase changes during playback, raw-route opt-in/erase, Low Power
Mode, battery consumption, Bluetooth controls, and confirmation that the current
track is never interrupted.

## Sprint 13 readiness

Sprint 12 is implementation-complete and ready for Sprint 13. Its physical-device
exit criteria are explicitly pending the consolidated final verification sprint.
