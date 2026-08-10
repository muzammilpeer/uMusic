# Beta Diagnostics Contract

Beta diagnostics are optional and disabled by default. Enabling them records only bounded lifetime counters for session lifecycle, playback-start success/failure, playback interruption, audio underrun, and model fallback. The payload contains framework/build versions and aggregate counts only.

It cannot represent track or playlist IDs, song metadata, timestamps, listening timelines, account identity, server URL, tokens, file paths, activity, location, calendar, HealthKit, or raw model features. The buffer has no networking dependency and never uploads. Export is an explicit user action; opting out immediately deletes accumulated counters.

TestFlight crash diagnostics supplied by Apple are governed separately by the tester's Apple analytics choices. Before inviting external testers, the release owner must configure TestFlight feedback/privacy text and verify App Store Connect access and retention.

Operational calculations:

- Playback-start success = successes / (successes + failures).
- Normal-session completion is a coarse stability indicator, not a substitute for MetricKit crash/hang evidence.
- Audio underrun and model-fallback counters are triage signals; reports require reproduction before code changes.

Raw personal data must never be requested in a beta-feedback ticket. Support should request the aggregate export, build number, device/OS, reproduction steps, and whether media was cached or streamed.
