# Sprint 07 report — taste and MP3 source adapters

Status: complete

## Delivered

- Feature-flagged adapter registry; disabled adapters return 404 and disappear
  from the adapter listing/UI.
- Audited adapter jobs with provenance, status, counts, errors, and operator
  attestation.
- Recursive server-folder MP3 importer restricted to resolved configured roots;
  traversal and paths outside those roots are rejected.
- Every acquired folder/YouTube file reuses quarantine, ffprobe/MP3 validation,
  checksum storage, duplicate detection, and transactional ingestion.
- Authorized taste metadata ingestion with exact, probable, unmatched, rejected,
  and confirmed states. Probable matches require explicit confirmation.
- Taste candidates never grant audio acquisition permission.
- Optional YouTube subprocess adapter, disabled by default, limited to public
  YouTube URLs, single-item operation, one concurrent job, maximum file size,
  authorization attestation, provenance, and audit trail.
- No cookies, credentials, DRM, paywall, age-gate, region, or access-control
  bypass mechanisms.
- Matching inbox and recent adapter-job web screen.

## Configuration

`UMUSIC_FOLDER_IMPORT_ENABLED`, `UMUSIC_TASTE_IMPORT_ENABLED`,
`UMUSIC_YOUTUBE_IMPORT_ENABLED`, `UMUSIC_IMPORT_ROOTS`, `UMUSIC_YTDLP_PATH`, and
`UMUSIC_YOUTUBE_MAX_ITEMS` control exposure and limits. YouTube stays off unless
the operator explicitly enables and installs the configured downloader binary.

## Verification

Tests cover feature flags, disabled endpoints, root traversal, exact/probable/
unmatched confidence, taste/audio permission separation, URL validation, and
mandatory YouTube attestation. All project quality gates pass.

The project is ready for Sprint 08 scheduling, operations, and product polish.
