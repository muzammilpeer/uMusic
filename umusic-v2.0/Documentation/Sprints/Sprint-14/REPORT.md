# Sprint 14 Report

Status: **Core ML ranker lifecycle and heuristic integration implemented and locally validated; a trained, signed production model and device performance evidence remain release gates**  
Date: 2026-08-10

## Delivered behavior

- Added a dedicated `UMusicML` module containing the model feature contract, cryptographic validation, lifecycle state machine, bounded batch scoring, and Core ML adapter.
- `SignedModelValidator` verifies the model SHA-256 digest, Curve25519 signature, signing-key identity, exact ordered feature schema, supported schema version, and minimum operating-system version before it issues the opaque receipt required to construct a lifecycle.
- The feature manifest fixes the first ranker input order to heuristic score, completion rate, skip rate, logarithmic exposure, offline availability, cyclical local-hour values, and scaled release year.
- Lifecycle modes support disabled, canary, shadow, and active operation. Canary validation rejects malformed input, non-finite output, incompatible batch size, and inference that exceeds the configured deadline.
- Active model failure immediately disables the model and returns control to the deterministic heuristic engine. Extreme finite scores are clamped before ordering.
- `LocalLearningStore` generates a bounded heuristic candidate set, derives model features locally, optionally invokes the model, and always applies policy reranking after model scoring.
- Shadow mode executes and records aggregate lifecycle outcomes without changing the user-visible order. Active mode records model and feature versions in the recommendation trace and reason codes.
- Manual queue priority remains outside automatic ranking. Calendar/content restrictions, including Ramadan behavior, remain authoritative because model ranking cannot bypass candidate policy filtering or final policy reranking.
- Recommendation results now expose execution mode, model version, feature version, and fallback code for local diagnostics.
- The bundled resource manifest explicitly reports model version `uninstalled`. No untrained or unsigned artifact is activated merely to satisfy packaging.
- Framework version advanced to `2.0.0-alpha.14`; resource metadata and public symbol-graph baselines were refreshed.

## Validation

- All 101 Swift tests pass.
- Ranker coverage verifies valid signatures, bad signatures, corrupt bytes, feature-schema mismatch, unsupported operating systems, deterministic canary/shadow/active transitions, NaN input, invalid model output, hard timeout, active rollback, extreme-score clamping, resource lookup, recommendation tracing, and policy-preserving integration.
- A deterministic synthetic scorer improves accuracy over its majority baseline and stays below the local 50 ms lifecycle diagnostic. This tests the integration contract, not production model quality.
- Generic iOS `UMusicCore` and macOS `UMusicApp` builds pass with code signing disabled.
- Architecture dependency checks and public production symbol-graph checks pass. SwiftPM continues to emit the known test-bundle symbol extraction warning after the required production graphs are validated.
- `git diff --check -- umusic-v2.0` passes.

## Boundaries and remaining gates

- There is no trained `.mlmodel`/`.mlmodelc` artifact from Sprint 13. The shipping manifest therefore remains `uninstalled`, and runtime recommendation behavior remains heuristic until a reviewed model is trained, signed, bundled, and activated.
- The Core ML adapter compiles, but real-model inference has not been exercised. Physical-device latency, memory, thermal, battery/energy, Neural Engine compatibility, and cross-device accuracy remain mandatory release evidence.
- Synthetic accuracy and latency tests do not prove that a future trained model beats the existing heuristic. Activation requires a completed model card, held-out evaluation, product review, and device measurements.
- Rollback currently means disabling the active model and returning immediately to the heuristic engine. Retaining and restoring a previously approved model artifact is deferred until signed model updates are designed.
- Lifecycle counters are aggregate, local, and in-memory. Persisted model-health history is not included in this sprint.
- The model is not downloaded from the backend, and no cloud or LLM inference occurs in the playback loop.
- No backend source, database migration, Docker service, or deployment was changed for Sprint 14.

## Next sprint entry

Sprint 15 should add explicit source-governance controls and adapters while keeping restricted sources disabled by default, preserving revocation behavior, and maintaining the local-first recommendation and privacy boundaries established through Sprint 14.
