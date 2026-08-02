# Sprint 03 report — reliable listening telemetry

Status: complete

## Delivered

- Append-only owner-scoped listening events with client-generated idempotency
  IDs and distinct play-attempt IDs.
- A batch API accepting up to 500 online or offline events, safely recognizing
  retries without creating duplicates.
- Event types for started, progress, paused, resumed, seeked, completed,
  skipped, liked, disliked, replayed, and queue removed.
- Persistent web-player event outbox in `localStorage`; failed/offline batches
  retry when connectivity returns.
- Fifteen-second playback heartbeats, capped at 30 seconds of credited listening
  time per event. Seek distance never counts as listening time.
- Rebuildable play facts with listening time, completion, early skip, replay,
  furthest position, event count, and latest explicit feedback.
- Completion at 90% or an explicit completion event; early skip at or below 20%.
- Raw client timestamps and server receipt timestamps retained independently,
  allowing late events and clock skew without mutating history.
- Like/dislike and queue-removal controls in the persistent player.
- Owner listening-history page plus immutable Django admin inspection.
- `python manage.py rebuild_play_facts` recovery command.

## Retention policy

Raw listening events are retained for the life of the owner's account. They
cannot be edited or individually deleted through the model or admin. Account
deletion remains the privacy boundary and removes owner data. Derived play facts
may be deleted and rebuilt at any time.

## Verification

- Duplicate/retried batches create exactly one event.
- Reordered offline events rebuild using client-time order.
- Clock skew, short tracks, early skips, completion inference, replay, seeking,
  feedback, and capped heartbeat credit are covered.
- Browser state keeps the same play-attempt ID across refresh restoration.
- Ruff, strict mypy, pytest, and branch coverage passed.

The codebase is ready for Sprint 04 activity, place, and immutable context
snapshots.
