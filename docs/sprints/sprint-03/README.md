# Sprint 03 — Reliable listening telemetry

## Goal

Collect trustworthy behavior on which learning can depend.

## Deliverables

- Append-only listening-event model and batch API.
- Client-generated idempotency IDs.
- Explicit heartbeat, completion, skip, seek, and replay rules.
- Derived play facts without destroying raw events.
- Like/dislike controls and event inspection UI.

## Exit criteria

- Retried batches do not duplicate events.
- Sessions reconstruct correctly after browser refresh.
- Late events, clock skew, seeks, short plays, skips, and completion are tested.

## Start

Use [PROMPT.md](PROMPT.md).

