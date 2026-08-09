# Sprint 0 Decision Register

Statuses: **Accepted** is the working v2 baseline; **Provisional** must be confirmed by its decision date; **Open** blocks the sprint named in `Blocks`.

| ID | Decision | Status | Working choice | Owner | Decide by | Blocks |
|---|---|---|---|---|---|---|
| D-001 | Minimum Apple OS | Provisional | iOS/iPadOS 17, macOS 14 | Product owner | Before Sprint 1 | Project settings, API availability |
| D-002 | Framework consumers | Provisional | uMusic app and extensions only for v2.0; public SDK compatibility starts after launch | Product owner | Before Sprint 1 | Public API breadth |
| D-003 | Persistence | Accepted | Core Data with three stores and explicit background contexts | Engineering | Done | Sprint 3 onward |
| D-004 | Playback engine | Accepted | AVPlayer-based coordinator; prototype restoration before production | Engineering | Done | Sprint 4 |
| D-005 | XCFramework linkage | Provisional | Static `UMusicCore.xcframework`; separate extension-safe product | Engineering | End Sprint 0 spike | Sprint 1 |
| D-006 | Model runtime | Accepted | Core ML local inference with deterministic heuristic fallback | Product + ML | Done | Sprints 11/14 |
| D-007 | Model delivery | Provisional | Bundled signed baseline; signed downloaded updates deferred until security review | Engineering | Before Sprint 14 | Sprint 14 |
| D-008 | Minimum performance device | Open | Nominate oldest supported physical iPhone matching D-001 | Product owner | Before spike measurements | Release budgets |
| D-009 | macOS launch scope | Provisional | Full library/player/export client; no HealthKit/Core Motion | Product owner | Before Sprint 1 | Target structure |
| D-010 | Personal-data sync | Accepted | No server upload/sync of learned profile in v2.0 | Product owner | Done | API/privacy |
| D-011 | Raw location | Accepted | Off by default; coarse local classification only; no normal coordinate log | Product owner | Done | Sprint 10 |
| D-012 | Ramadan behavior | Accepted | Explicit preference and selected playlist; never infer religion | Product owner | Done | Sprint 12 |
| D-013 | v1 migration | Accepted | Not part of initial build; copy-first optional adapter designed in Sprint 18 | Engineering | Done | Sprint 18 |

## Approval needed before Sprint 1

The product owner should confirm D-001, D-002, D-008, and D-009. Work may use their provisional values for disposable spikes, but production project settings should not be frozen until confirmation.

## Change control

Changing an Accepted decision requires a superseding ADR describing new evidence, migration impact, privacy impact, and which tests/budgets must be repeated. A decision may not be changed only to make a failing validation disappear.

