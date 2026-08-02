# Sprint 01 — Accounts, MP3 library, and storage

**Status:** Complete — see [REPORT.md](REPORT.md).

## Goal

Safely upload, validate, store, and browse MP3 files.

## Deliverables

- Custom user and single-owner bootstrap.
- Track, artist, album, artwork, audio file, import job, and audit models.
- Quarantine, ffprobe MP3 validation, ID3/artwork extraction, and SHA-256 storage.
- Duplicate and corrupt-file handling with transactional imports.
- Storage abstraction for local Docker volumes and mounted POSIX shared storage,
  including GFS/GlusterFS-style mounts.
- Admin/library pages, REST upload API, and import failure UI.

## Exit criteria

- Valid MP3 files appear in the library.
- Mislabeled, corrupt, and oversized inputs are rejected.
- Duplicate bytes do not create duplicate stored objects.
- Web and workers access the same logical storage namespace.
- Storage contract tests pass for local and mounted backends.

## Start

Use [PROMPT.md](PROMPT.md).
