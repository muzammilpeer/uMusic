# Sprint 13 report — field learning and release quality

## Release status

**Release candidate; physical iPhone field verification is BLOCKED/pending.**

The implementation, isolated restore, and automated server-to-offline journey pass.
The project is not declared fully released because this environment cannot prove a
30-minute locked-screen outdoor cycling/running session, Bluetooth behavior, HealthKit
permission/save, or measured device battery consumption.

## Delivered

- Owner-scoped evaluation dashboard at `/library/evaluation/` comparing immutable
  recommendation versions by activity, completion, early skips, approval, diversity,
  coverage, explanation rate, and exploration acceptance.
- Explicit deterministic-fallback status when listening evidence is insufficient.
- Privacy dashboard at `/library/privacy/` with no-store JSON export, separately
  confirmed listening/learning deletion, account deletion, existing place-forget
  controls, and device revocation.
- Export includes personal contexts and history but excludes passwords, device token
  hashes/secrets, authorization headers, and signed URLs.
- Threat model, security-release criteria, operations/incident runbook, backup
  procedure, and executable release checklist.
- Writable persistent backup volume in development Compose; production bind-mount
  ownership requirements and `UMUSIC_BACKUP_PATH` are documented.
- Full simulated field journey test: cycling recommendation generation → device sync
  plan → signed manifest downloads → SHA-256 verification → acknowledgement → three
  MP3s read sequentially after an explicit no-network boundary.

## Measured verification

- 84 Django/Python tests pass.
- Coverage: 85%, meeting the configured release gate.
- Ruff passes; strict mypy passes across 128 Python source files.
- Migration drift check: no changes detected.
- 5 Swift core tests pass in Swift 5 language mode.
- Generic iOS Simulator build passes for iPhone/iPad; generic macOS build passes.
- Local Docker web, worker, scheduler, PostgreSQL, and Redis are running; readiness
  reports database and Redis healthy, and Prometheus readiness metrics equal 1.
- Production Compose renders successfully with no published origin ports; only
  internal `expose` entries are present behind the outbound Cloudflare Tunnel.
- Live application backup created at `/backups/sprint13-2026-08-02`.
- Isolated restore applied every migration, installed 166 fixture objects, and verified
  all 9 media references.
- Automated offline workout journey downloaded, verified, acknowledged, and locally
  replayed 3/3 MP3 files without server calls after the airplane boundary.

## Recommendation decision

No valid multi-week comparison can be claimed from the currently available evidence.
Release therefore retains `generator-v1`, immutable seeds/inputs/model versions,
reason codes, hard explicit exclusions, and deterministic cold-start behavior. The
dashboard will support a real comparison after several weeks of reliable field events.

## Known limitations and required physical gate

Run [the release checklist](../../12-release-checklist.md) on the target iPhone. At
minimum, record device/OS, a 30-minute locked-screen cycling or running session,
airplane-mode queue transitions, Bluetooth/Control Center commands, location-denied
manual operation, HealthKit allow/deny, route opt-in/erase, reconnection continuation,
deferred-event reconciliation, and start/end battery percentage.

Any critical data-loss, authentication, privacy, corrupt-download, or background-
playback defect blocks release. When every physical item passes, this report can be
updated from **release candidate** to **released** without another implementation
sprint.
