# Engineering Budgets

These are initial pass/fail targets. Measure release gates on the nominated minimum physical iPhone with a 25,000-track catalog and representative artwork. Simulator numbers are diagnostic only.

| Area | Scenario | Target | Measurement |
|---|---|---:|---|
| Cold launch | process start to interactive cached Home | p95 ≤ 1.5 s | XCTest signpost metric, 10 runs |
| Warm launch | process start to interactive cached Home | p95 ≤ 0.8 s | XCTest signpost metric, 10 runs |
| Restore UI | launch to prior mini-player snapshot visible | p95 ≤ 300 ms | signposts |
| Local playback | tap to audible verified cached MP3 | p95 ≤ 250 ms | audio/signpost instrumentation |
| Stream playback | tap to audible on stable Wi-Fi | p95 ≤ 2.0 s | controlled network profile |
| Local search | query to first results, 25k tracks | p95 ≤ 100 ms | XCTest measure |
| Recommendation | rank/refine queue from 25k catalog | p95 ≤ 150 ms | release build, 30 fixtures |
| ML inference | prebuilt candidate feature matrix | p95 ≤ 50 ms | Core ML metrics |
| Main-thread stall | during sync/export/download | no stall > 100 ms attributable to app work | Instruments Hangs |
| Memory | normal playback + cached library | ≤ 150 MB steady state | Instruments/XCTest |
| Memory | 1 GB streaming export | peak increase ≤ 30 MB | allocation metric |
| Database | routine listening durable writes | ≤ 1 checkpoint/15 s; event batch ≥ 25 events or 120 s | store instrumentation |
| Network | idle configured app | zero periodic requests | Network instrument |
| Sensors | no active listening/context feature | zero motion/location/HealthKit activity | Energy Log |
| Location | Low Energy listening context | event-driven/coarse; no 1–3 minute polling timer | code + Energy Log audit |
| Downloads | quota | committed media never exceeds quota except one explicitly reported in-flight reservation | integration test |
| Audio | 60-minute cached playback under UI load | zero app-caused underruns | device run |
| Battery | 60-minute cached playback, screen off | baseline audio + ≤ 3 percentage-point app overhead versus context disabled | controlled A/B; report device health |
| App size | app + framework + baseline model | initial target ≤ 100 MB download | archive report |
| Model | baseline compressed resource | ≤ 15 MB | build artifact |

## Measurement rules

- Record device model, OS, battery health, thermal state, build configuration, catalog shape, media source, network profile, and run count.
- Report median and p95; do not average away outliers.
- Compare context-enabled and context-disabled runs under the same conditions.
- A target change requires evidence, product impact, an ADR, and explicit approval.
- Functional correctness and privacy are never traded away to meet a performance number.

