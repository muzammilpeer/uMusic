# Sprint 0 Feasibility Prototype Plan

All spikes are disposable and live under `Prototypes/` when executed. They must not share identifiers, stores, or source files with v1 or become production code by accident.

## P-001 AVPlayer restoration without autoplay

- **Question:** Can a saved track/queue/seek snapshot render immediately and prepare media without producing audio until the user acts?
- **Inputs:** local MP3 fixture, remote test URL, missing-file case, interruption case.
- **Procedure:** persist Codable snapshot; relaunch; publish UI snapshot synchronously; asynchronously attach asset; seek with tolerance; leave paused; issue Play before and after readiness.
- **Measure:** snapshot-visible time, ready time, seek accuracy, accidental audio, main-thread stalls.
- **Pass:** no autoplay in 100 launches; UI ≤ 300 ms p95; seek within 500 ms; early Play is honored; missing media yields recoverable state.
- **Cleanup:** remove spike target and generated stores; retain report and any ADR evidence.
- **De-risks:** Sprints 4–5.

## P-002 XCFramework resources and extension boundary

- **Question:** Can static framework slices locate Core ML/JSON resources in app, tests, and an extension-safe product?
- **Procedure:** build minimal iOS device/simulator/macOS slices, integrate into host targets, resolve a versioned fixture through the internal bundle, verify extension target links only import APIs.
- **Measure:** archive/link success, resource URL/hash, binary size, exported symbols.
- **Pass:** all slices load the same verified resource; no forbidden playback/sensor symbol in extension product; API baseline generated.
- **De-risks:** Sprints 1, 14, and 15.

## P-003 Background download restoration

- **Question:** Can download tasks survive suspension/termination and reconcile safely into a quota-managed content-addressed cache?
- **Procedure:** use `URLSessionDownloadDelegate`; persist task mapping; interrupt at multiple percentages; relaunch; verify checksum; atomically move; simulate expired URL/disk full.
- **Measure:** successful restoration rate, duplicate files/tasks, quota reservation, main-thread work.
- **Pass:** exactly one committed verified file per identity; recoverable errors; no async completion-handler misuse; no quota violation.
- **De-risks:** Sprint 6.

## P-004 Bounded-memory Core Data export

- **Question:** Can a 1 GB logical telemetry store export JSONL/CSV without loading rows into memory?
- **Procedure:** generate synthetic non-sensitive rows; fetch in batches with autorelease scopes; stream output; cancel midway; retry; delete temporary output.
- **Measure:** peak memory delta, elapsed time, cleanup, row/hash validation.
- **Pass:** ≤ 30 MB peak increase, deterministic manifest/count/hash, cancellation cleanup, no live-store mutation.
- **De-risks:** Sprints 13 and 16.

## P-005 Local ranking at catalog scale

- **Question:** Can candidate generation and a small Core ML ranker meet the queue latency budget for 25,000 tracks?
- **Procedure:** generate deterministic metadata/features; compare heuristic, Accelerate-friendly linear model, and small Core ML model; prefilter candidates; rank/rerank 30 times under normal and Low Power Mode.
- **Measure:** median/p95 time, memory, model size, thermal/energy signals, deterministic constraints.
- **Pass:** end-to-end p95 ≤ 150 ms, model inference p95 ≤ 50 ms, model ≤ 15 MB, manual/diversity policies always hold, fallback succeeds.
- **De-risks:** Sprints 11 and 14.

## Required spike report template

Each `Prototypes/<ID>/REPORT.md` records commit/build, device/OS, procedure, raw measurements, pass/fail, unexpected behavior, artifacts, cleanup, and resulting ADR update. A failed spike changes design before production implementation; it does not lower a budget automatically.

