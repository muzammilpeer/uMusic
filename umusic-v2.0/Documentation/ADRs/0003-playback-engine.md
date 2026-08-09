# ADR 0003: AVPlayer Playback Coordinator

- Status: Accepted; physical-device performance evidence pending
- Date: 2026-08-09

## Decision

Use a single actor-owned playback coordinator with an AVPlayer adapter for MP3 local/remote playback and MediaPlayer integration. Persist queue/track/seek intent independently of AVPlayer objects.

## Consequences

The UI observes immutable throttled snapshots. Restoration prepares paused media and never autoplays. P-001's deterministic contract and generic iOS compile passed; real seek/audio/latency measurements remain before Sprint 0 closes. If physical testing exposes unacceptable restoration/gap behavior, a superseding ADR must compare AVQueuePlayer or AVAudioEngine without weakening system-control support.
