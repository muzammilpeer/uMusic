# Sprint 11 — Offline sync, rolling cache, and continuation

## Goal

Prepare sessions for offline use and extend playback dynamically when online.

## Deliverables

- Session preparation and offline manifests.
- Resumable background downloads and SHA-256 validation.
- Wi-Fi/charging rules, storage quotas, and pinned prepared files.
- Immutable offline queues and idempotent deferred events.
- Separate bounded rolling cache for streamed/prefetched tracks.
- Queue continuation when the playable pool falls below a threshold.
- Immediate next-track streaming and later-track prefetching.

## Exit criteria

- A prepared playlist plays in airplane mode.
- Interrupted downloads resume without corrupt files.
- Prepared/pinned tracks are not evicted mid-session.
- Queue exhaustion extends playback online.
- Network loss falls back to cached tracks and stops gracefully.
- Offline events upload once and only once.

## Start

Use [PROMPT.md](PROMPT.md).

