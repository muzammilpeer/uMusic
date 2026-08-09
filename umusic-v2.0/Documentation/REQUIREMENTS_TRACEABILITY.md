# Requirements-to-Sprint Traceability

| Requirement | Primary sprint(s) | Evidence expected |
|---|---|---|
| Separate v2 workspace and framework/UI split | 0–1 | boundary tests, XCFramework build |
| Account, server URL, Keychain, keep signed in, logout | 2 | auth/state/redaction tests |
| Complete metadata and deliberate sync | 3 | API fixtures, migration/scale tests |
| Mini/full player and system controls | 4 | UI/remote-command tests, latency |
| Same song/queue/position restoration without autoplay | 5 | relaunch and corruption tests |
| Offline quota, unmetered default, shared cache | 6 | background/quota/airplane tests |
| Library, search, manual playlists/queue | 7 | UI/accessibility/conflict tests |
| Start Listening and last 10 days | 8, 11 | cold-start/history/ranker tests |
| Efficient behavioral logging and retention | 9 | write/storage/reducer/expiry tests |
| Activity, location, route, fitness context | 10 | permission/energy/platform tests |
| Local next-track prediction | 11, 14 | golden ranking and model metrics |
| Ramadan explicit preference | 12 | policy/calendar/no-inference tests |
| Smart playlist auto-grow toggle/audit | 12 | default-off, cap, undo tests |
| Data export and Mac analysis | 13, 16 | round-trip/redaction/memory tests |
| Share URL to server download job | 15 | extension/idempotency/security tests |
| Optional visualizer | 16 | Reduce Motion/energy/underrun tests |
| Theme and accessibility | 1, 8, 17 | platform accessibility matrix |
| Fast UI and correct concurrency | all; harden 18 | Hangs, actors, performance budgets |
| Safe optional v1 migration | 18 | copy-first recovery/rollback tests |
| Beta/release gates | 19 | signed release report |

Any new requirement must be assigned to a sprint and given measurable evidence before implementation starts.

