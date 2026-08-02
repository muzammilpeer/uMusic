# uMusic v1 release checklist

Status values: PASS, FAIL, BLOCKED (requires physical device/external environment).

## Automated release gates

- [ ] Python tests, Ruff, strict mypy, migration check, and coverage gate pass.
- [ ] Swift core tests and generic iPhone/iPad/macOS builds pass in Swift 5 mode.
- [ ] Fresh-database migrations and upgraded deployment start successfully.
- [ ] Local and mounted-filesystem storage contract tests pass.
- [ ] Authentication, revoked download, upload validation, Range streaming, event
      idempotency, continuation, sync acknowledgement, and privacy tests pass.
- [ ] Production Compose publishes no origin service ports.
- [ ] Isolated backup restore loads and verifies every media checksum reference.
- [ ] Data export contains owner data and no password/token hashes or secrets.
- [ ] Deterministic recommendation fallback is visible when evidence is insufficient.

## Physical iPhone/iPad gates

- [ ] Prepare cycling and focus sessions on Wi-Fi; all MP3s report downloaded.
- [ ] Enable airplane mode and play first, next, previous, seek, and full queue transition.
- [ ] Lock the iPhone for at least 30 minutes; use Lock Screen, Control Center, and
      Bluetooth controls without playback termination.
- [ ] Run/cycle outdoors; verify phase changes never interrupt the current track.
- [ ] Deny location and HealthKit independently; manual activity/place still works.
- [ ] Test opt-in route creation and erase; verify no route exists when disabled.
- [ ] Reconnect near queue exhaustion; immediate continuation streams and later tracks
      enter rolling cache. Repeat with timeout/network loss.
- [ ] Force-quit during download and resume; test low storage, bad checksum, Wi-Fi-only,
      charging-only, and Low Power Mode.
- [ ] Reconnect and verify offline listening events upload exactly once.
- [ ] Record battery percentage, device/OS, session duration, network state, and failures.

## Release decision

Release is **blocked** by any critical data-loss, authentication, owner-isolation,
privacy, corrupt-download, or locked-screen playback defect. It is also blocked until
the backup/restore and full server-to-airplane-mode-workout exercises pass. Recommendation
quality may ship on the documented deterministic fallback until multi-week evidence is
large enough for a valid comparison.
