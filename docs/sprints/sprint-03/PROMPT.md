# Sprint 03 implementation prompt

```text
Implement Sprint 03 of uMusic after verifying Sprint 02. Add append-only,
idempotent batch listening-event ingestion and update the web player to emit
started, progress, paused, resumed, seeked, completed, skipped, liked, disliked,
replayed, and queue-removed events. Define heartbeat and derived play-fact rules
explicitly. Preserve raw events and make aggregation rebuildable.

Test duplicate and reordered batches, clock skew, refresh, retries, seeks, early
and late skips, short tracks, replay, and completion. Run all checks, update the
event API contract, and report Sprint 04 readiness.
```

