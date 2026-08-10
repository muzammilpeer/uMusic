# Sprint 13 Report

Status: **Streaming research packages, trainer dataset contract, and read-only macOS inspector implemented and locally validated; 1 GB device memory profiling and a concrete encryption provider remain release gates**  
Date: 2026-08-10

## Delivered behavior

- Sanitized and Full research exports now produce versioned `.umusicresearch` packages with a JSON schema manifest, record counts, independently decodable JSONL files, and a fixed-schema CSV feature dataset.
- Writers encode and write one record at a time instead of constructing a monolithic export payload. Cancellation is checked every 256 records.
- Export startup estimates required space and fails before writing when capacity is insufficient.
- Partial packages are removed after cancellation or failure. Protected temporary files use complete file protection and owner-only POSIX permissions.
- Old temporary packages are cleaned before a new export; an explicit cleanup capability is also available.
- `ResearchExportEncrypting` defines an optional package-encryption boundary without silently choosing or storing an encryption key.
- Sanitized packages omit track snapshots, sessions, consent strings, and free-form artist/album/genre/language learned keys. The manifest records the explicit denylist for credentials, server URL, username, paths, coordinates, raw HealthKit values, and accessory identifiers.
- Full exports require a fresh five-minute preview token. The UI previews event/observation counts and clearly identifies track metadata, complete timeline, and coarse context before confirmation.
- The Learning & Privacy screen prepares the new sanitized package by default and exposes Full only through the preview/confirmation flow.
- `TrainingFeatureBuilder` deterministically joins observations to captured coarse context, clamps listened ratio, and derives completion/skip labels from explicit end reasons.
- Dataset splitting is chronological by whole playback session, preventing a session from crossing training, validation, and test partitions.
- A deterministic majority baseline reports example count, completion rate, and majority accuracy.
- Training dataset documentation and a model-card template define provenance, split evidence, feature/label review, baseline comparison, privacy, latency, energy, activation, and rollback fields.
- New `UMusicInspector` and macOS `UMusicDataInspector` products validate package manifests/files, display record counts, reject malformed/path-traversing packages, and copy selected stores to protected read-only temporary files before inspection.
- Framework version advanced to `2.0.0-alpha.13`; resource manifest and public API baselines were refreshed.

## Validation

- 95 Swift tests pass.
- Sprint coverage includes a 20,000-observation streaming package, JSONL record counts, schema round-trip, denylist payload scanning, Full confirmation, cancellation cleanup, low-disk failure, temporary cleanup, malformed packages, read-only store copies, deterministic features, chronological ordering, session leakage prevention, and bounded baseline metrics.
- Generic iOS and macOS `UMusicApp` builds pass with code signing disabled.
- The macOS `UMusicDataInspector` build passes with code signing disabled.
- Architecture checks and public production symbol-graph baselines pass. SwiftPM still emits the known test-bundle symbol-graph warning after checking production graphs.
- `git diff --check` passes.

## Boundaries and remaining gates

- The JSONL/CSV writer has bounded incremental encoding, but the current Sprint 9 learning store itself remains a resident JSON document. A true 1 GB source-store test and the ≤30 MB peak-memory budget require a future paged/Core Data source reader plus Instruments measurement on supported hardware.
- The validated large fixture contains 20,000 observations rather than 1 GB of logical telemetry; it proves streaming behavior and record integrity, not the final physical-device memory gate.
- `.umusicresearch` is currently a protected directory package, not a compressed ZIP. A concrete `ResearchExportEncrypting`/archive provider is intentionally not selected yet.
- The inspector validates export packages and makes read-only copies of selected store files. It does not mutate, migrate, or write back to a live Core Data store and does not yet provide arbitrary SQL exploration.
- Full exports remain highly sensitive even with preview. They are local until the user explicitly invokes the system share flow.
- No backend source, Docker service, database migration, or deployment was changed for Sprint 13.

## Next sprint entry

Sprint 14 should place a bounded Core ML ranker behind the existing recommendation engine with feature-manifest validation, signed model resources, canary inference, shadow mode, activation and rollback, reason/version tracing, and unconditional heuristic fallback.
