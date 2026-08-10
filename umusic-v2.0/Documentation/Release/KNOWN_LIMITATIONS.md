# Beta 1 Known Limitations

- No minimum physical iPhone has been nominated, so launch, memory, Hangs, Energy Log, battery, and 60-minute underrun gates lack release evidence.
- TestFlight has not been archived, signed, uploaded, or assigned to a cohort in this environment.
- The v1 migration adapter creates a validated `.ready` package but does not import it into live v2 stores or expose migration UI.
- Learning, playlist, and queue stores remain JSON-backed; their 1 GB/large-data memory targets are unresolved.
- No production Core ML model is installed. Heuristic ranking remains the safe fallback.
- Full multilingual localization and signed-device accessibility validation remain open.
- Keychain/App Group entitlements, merged privacy report, export lifecycle, TLS failure drills, and dependency vulnerability scanning require release/staging environments.
- macOS has no real output-route classifier and intentionally reports unknown rather than fabricating data.
- Beta diagnostics are aggregate-only and user-exported; there is no automatic crash/playback dashboard backend.
