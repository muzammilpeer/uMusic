# P-001 Playback Restore Probe

Disposable Swift prototype for the restoration contract: decode a snapshot synchronously, publish it before media preparation, prepare/seek asynchronously, never autoplay after launch, and remember an explicit Play request made during preparation.

Run:

```sh
swift test --package-path umusic-v2.0/Prototypes/P-001-PlaybackRestore
```

The controlled-player tests validate state semantics deterministically. The AVPlayer adapter provides the real Apple integration seam; physical-device audio/latency validation remains required before the spike can pass completely.

