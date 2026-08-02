# Sprint 07 — Taste imports and MP3 source adapters

## Goal

Import external taste information and authorized MP3 sources through replaceable,
audited adapters.

## Deliverables

- Feature-flagged generic import-adapter interface.
- MP3 server-folder importer restricted to configured roots.
- Authorized playlist/export metadata import and matching inbox.
- Exact, probable, unmatched, rejected, and confirmed match states.
- Optional private YouTube adapter with attestation, provenance, rate/concurrency
  limits, and the normal MP3 validation pipeline.

## Exit criteria

- Disabled adapters expose no job or UI entry points.
- All files pass the Sprint 01 ingestion pipeline.
- Uncertain metadata matches require confirmation.
- Taste data never implies audio-copy permission.
- No DRM, credential, paywall, or access-control bypass exists.

## Start

Use [PROMPT.md](PROMPT.md).

