# Beta / Release Candidate Checklist

Release owner: **Unassigned**

Minimum test device: **Unassigned (D-008)**

Candidate: `2.0.0-beta.1` / framework `2.0.0-alpha.19`

`PASS` requires linked evidence and a signer/date. `BLOCKED` cannot be waived in this file; a changed target needs evidence, ADR, and explicit user approval.

| Gate | State | Evidence / required sign-off |
|---|---|---|
| Debug and release automated suites | PASS | Sprint 19 report; engineering |
| Generic iOS/macOS compile | PASS | Unsigned generic builds; engineering |
| Public API and persistence-schema freeze | PASS | `release-freeze.json` plus API baselines; engineering |
| 25k catalog search/ranking | PASS locally | Sprint 18 performance evidence; physical-device confirmation pending |
| Offline/download recovery | PASS locally | Download coordinator tests; signed-device restoration pending |
| Backup/restore and corrupt archive | PASS locally | Backup runbook and automated recovery drill |
| v1 migration retry/rollback | PASS package level | Sprint 18 migration report; live-store import is blocked |
| Model validation/fallback/rollback | PASS without production model | Model lifecycle tests; production artifact pending |
| Crash-free sessions >99.8% | BLOCKED | TestFlight/MetricKit cohort evidence unavailable |
| Playback-start success >99.5% | BLOCKED | Beta cohort aggregate evidence unavailable |
| Energy/audio/memory/launch budgets | BLOCKED | Minimum-device Instruments evidence unavailable |
| Signed capabilities and privacy report | BLOCKED | Archive entitlement/privacy review required |
| Security/TLS/dependency review | BLOCKED | Sprint 18 audit open items |
| Accessibility/localization device matrix | BLOCKED | Sprint 17 open items |
| TestFlight privacy-safe cohort | BLOCKED | App Store Connect signing/upload and user authorization required |
| Product owner accepts limitations | BLOCKED | Explicit user acceptance required |

Release decision: **NO-GO** until every BLOCKED row is resolved. No build is represented as signed or distributed by this report.
