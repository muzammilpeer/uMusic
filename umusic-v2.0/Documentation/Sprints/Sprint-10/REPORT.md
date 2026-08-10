# Sprint 10 Report

Status: **Manual activity and privacy/energy context foundation implemented and locally validated; entitlement-backed sensor adapters remain a device integration gate**  
Date: 2026-08-09

## Delivered behavior

- A new `ContextManaging` capability is exposed by `UMusicClient` and injected into the SwiftUI app.
- Manual activity selection supports Listening, Walking, Running, Cycling, Gym, Focus, and Relaxation and remains available regardless of permissions or adapter support.
- Activity & Context settings provide an explicit Start/Finish lifecycle. Opening the screen starts no sensor or context collection.
- uMusic Low Energy Mode defaults on and is accurately described as an app policy, not iOS Low Power Mode.
- Independent opt-ins for motion, workout summaries, coarse location, audio-route category, and network class.
- Each signal records granted/denied/revoked consent in the local learning store and stops its adapter immediately when disabled.
- Low Energy motion policy requests a bounded five-second sample only after the user presses Sample Activity Now. A suggestion never silently replaces the manual activity.
- Indoor Gym, Focus, and Relaxation sessions never invoke location.
- Outdoor Walking, Running, and Cycling sessions may request one coarse place classification when enabled, then stop the location adapter. No coordinate or route trail exists in the domain schema.
- Context session Finish stops motion, workout, and location adapters.
- Context snapshots store only local hour, weekday, time-zone offset, coarse activity/source/confidence, coarse place class, route category, network class, and the app energy policy.
- Material context changes flow into Sprint 9's actor-owned event batcher; missing context always degrades to `unknown` and does not block playback or sync.
- System audio-route categorization on iOS distinguishes built-in, wired, Bluetooth, AirPlay, and car output without storing accessory names or identifiers. No battery percentage is claimed.
- System network classification uses one bounded path query and maps offline/metered/unmetered; Wi-Fi and Ethernet are unmetered.
- iPhone-only motion/workout controls are compile-time excluded from macOS UI. Manual activity, route, network, and low-energy controls remain cross-platform.
- Existing Sprint 9 context records decode with safe defaults for the new fields.
- Framework version advanced to `2.0.0-alpha.10`; public API baselines were refreshed.

## Validation

- 77 Swift tests pass.
- Coverage includes denied, restricted, and revoked sources; manual override; explicit-only sampling; cancellation/timeout fallback; indoor no-location behavior; outdoor one-shot classification; session cleanup; low-energy defaults; unsupported adapters; context UI platform gates; and all prior regression suites.
- Generic iOS and macOS app builds pass with code signing disabled.
- Public production symbol-graph baselines pass. SwiftPM still emits its known test-bundle symbol-graph warning after checking the required production graphs.

## Boundaries and remaining gates

- Core Motion, HealthKit workout-session, and Core Location system adapters are represented by tested injectable protocols but are intentionally not enabled in the live composition yet. The generated SwiftPM app target does not yet carry reviewed usage descriptions, HealthKit capability, or signed entitlements. Enabling those APIs before target configuration would create permission/runtime risk.
- Consequently, live Sprint 10 currently provides manual activity plus system route/network context. Motion, workout, and coarse-location controls show unavailable until signed host-target adapters are installed.
- Workout summary values are not persisted yet; only the event-driven lifecycle contract exists. Raw HealthKit samples are never part of the learning schema.
- Route/network context is captured at explicit context start. Continuous route monitoring is not enabled; a future event adapter may submit a material route change without polling.
- Raw-route opt-in, coordinate export, BLE scanning, accessory IDs, and headset battery work were not added.
- Physical-device permission prompts, revocation through Settings, background transitions, and battery/CPU measurements remain mandatory before activating the three entitlement-backed adapters.
- No backend changes or Docker deployment were required.

## Next sprint entry

Sprint 11 should implement the deterministic heuristic recommendation engine with hierarchical context backoff, decayed affinities, exposure-aware scoring, exploration, diversity/repetition constraints, reason codes, bounded fallback, Start Listening integration, and queue refill while preserving manual intent.
