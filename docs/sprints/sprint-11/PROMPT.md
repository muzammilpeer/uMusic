# Sprint 11 implementation prompt

```text
Implement Sprint 11 of uMusic after verifying Sprint 10. Add session preparation,
manifest diff, background/resumable MP3 downloads, SHA-256 verification, local
metadata/artwork, quotas, pinning, Wi-Fi/charging settings, immutable offline
queues, and idempotent deferred events.

Create a separate bounded rolling cache. When the playable pool is nearly empty
and the server is reachable, request a context-aware continuation, stream the
immediate track, and prefetch later tracks. Never evict prepared/pinned music
during its session. In network failure, finish the current track, use compatible
cached tracks, and stop cleanly.

Test app termination, resume, low storage, checksum failure, eviction, online
extension, timeout, mid-stream network loss, airplane mode, and event replay.
Run all checks and report Sprint 12 readiness.
```

