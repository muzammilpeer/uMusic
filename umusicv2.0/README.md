# uMusic 2.0 — Ground-Up Product Plan

Status: planning baseline  
Platforms: iPhone first; iPad and macOS compatible  
UI: SwiftUI  
Core delivery: `UMusicCore.xcframework` plus a thin `UMusicApp` integration target

uMusic 2.0 is a private, self-hosted, offline-first music experience built around one primary action: **Start Listening**. The server supplies authenticated library, playlist, artwork, and audio data. The Apple client owns playback, observation, privacy controls, local learning, prediction, queue construction, offline storage, and restoration.

This folder is deliberately independent of the existing application. It is a specification, not an instruction to migrate or delete v1 code.

## Documents

- [PROJECT_PLAN.md](PROJECT_PLAN.md) — product goals, scope, requirements, risks, and acceptance criteria
- [NAVIGATION_AND_UX.md](NAVIGATION_AND_UX.md) — information architecture and screen behavior
- [ARCHITECTURE.md](ARCHITECTURE.md) — modules, concurrency, persistence, playback, sync, and XCFramework boundary
- [DATA_AND_PRIVACY.md](DATA_AND_PRIVACY.md) — metadata, event schema, aggregation, retention, export, and permissions
- [API_CONTRACT.md](API_CONTRACT.md) — client/server request and response contracts
- [ML_AND_PROMPTS.md](ML_AND_PROMPTS.md) — cold start, ranking, compact learning records, evaluation, and LLM prompts
- [SPRINTS.md](SPRINTS.md) — phased implementation plan with gates and definitions of done

## Product principles

1. One-tap listening must work from day one, before personalization exists.
2. Manual control always overrides automatic behavior.
3. Playback remains useful offline and restores without auto-playing.
4. Personal context is local-first, minimized, explainable, and revocable.
5. Recommendation quality must never block playback.
6. The main actor is reserved for UI state and Apple framework calls that require it; I/O, parsing, aggregation, and inference run off the main actor.
7. The framework contains product capability; the app target contains presentation and composition.

## Decisions that must be validated before implementation

- Deployment target and whether the XCFramework must support third-party apps or only uMusic.
- Core Data versus SwiftData. This plan selects Core Data for mature migration/export tooling and explicit background contexts.
- On-device model family and minimum supported hardware.
- Whether macOS is a full player at launch or an inspection/export companion first.
- Ramadan behavior: the default proposed here is an optional user preference with easy manual override, never an assumption based only on location or identity.

