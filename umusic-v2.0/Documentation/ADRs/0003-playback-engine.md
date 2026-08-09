# ADR 0003: AVPlayer Playback Coordinator

- Status: Accepted pending P-001 evidence
- Date: 2026-08-09

## Decision

Use a single actor-owned playback coordinator with an AVPlayer adapter for MP3 local/remote playback and MediaPlayer integration. Persist queue/track/seek intent independently of AVPlayer objects.

## Consequences

The UI observes immutable throttled snapshots. Restoration prepares paused media and never autoplays. If P-001 exposes unacceptable restoration/gap behavior, a superseding ADR must compare AVQueuePlayer or AVAudioEngine without weakening system-control support.

