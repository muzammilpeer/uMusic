# Sprint 4 Report

Status: **Playback foundation implemented and locally validated; physical-device measurements remain**  
Date: 2026-08-09

## Delivered behavior

- One actor-owned `PlaybackCoordinator` controls the supplied in-memory track list and publishes bounded immutable snapshots.
- AVPlayer adapter with preparation, playback, pause, seek, periodic position, completion, interruption, output-route-loss, and failure events.
- Cache-first media source seam. Existing local files are selected before any network ticket request.
- Authenticated playback-ticket client and Django `/api/v2/media/playback-tickets` endpoint.
- Five-minute signed stream tickets scoped to one user and track, with byte-range support and no bearer token in the AVPlayer URL.
- Standard Now Playing metadata and supported remote commands: play, pause, next, previous, absolute seek, and ±15-second skips.
- Interruption policy records whether audio was playing and resumes only when the system permits it and user intent remains play.
- Losing an output route pauses playback and clears automatic resume intent.
- Stale asynchronous preparation is discarded using a preparation identifier.
- Full Now screen basics: metadata, artwork placeholder, scrubber, play/pause, next/previous, and ±15 seconds.
- Global mini player installed with a safe-area inset, so Library and other tab content remains reachable.
- Selecting a cached Library track supplies the current cached list as the temporary Sprint 4 queue.
- Framework version advanced to `2.0.0-alpha.4`.

## Validation

- 29 Swift tests pass, including cache preference, expired-ticket refusal, transition sequencing, completion advance, output-route pause, remote-command routing, architecture constraints, and all previous sprint coverage.
- Generic iOS and macOS builds pass with code signing disabled.
- 17 affected Django tests pass, including signed range streaming and cross-track ticket rejection.
- Ruff and Django system checks pass.

## Sprint boundaries and remaining gates

- The queue is intentionally in memory. Durable queue mutations, checkpointing, last-track/seek restoration, and no-autoplay relaunch behavior belong to Sprint 5.
- Offline download/index implementation still belongs to Sprint 6; `EmptyMediaCache` is the live placeholder until the shared cache index exists.
- Artwork retrieval and Now Playing artwork are not yet implemented.
- The full player does not yet expose volume. Apple recommends system volume controls; any in-app volume surface requires platform-specific UX review.
- Startup-to-audible latency, underruns, Bluetooth/headset commands, Lock Screen controls, interruptions, and route changes still require a signed physical-device run.
- Stream tickets are signed but not encrypted; they contain only internal user/track identifiers and expire quickly. Servers must avoid logging ticket query values.
- Docker services were not rebuilt or deployed during this sprint.

## Next sprint entry

Sprint 5 should persist the queue, supplied/manual origin, track snapshot, seek position, source identity, and paused intent. Relaunch must show the previous mini player immediately but must never autoplay.
