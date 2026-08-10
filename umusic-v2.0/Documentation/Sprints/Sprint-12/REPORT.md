# Sprint 12 Report

Status: **Explicit Ramadan preferences, calendar windows, and reversible smart playlists implemented and Apple-validated; backend framework tests await a configured runtime**  
Date: 2026-08-10

## Delivered behavior

- A persisted `CalendarPreferenceManaging` capability exposes Off, Suggest, and Prefer choices. Off remains the default.
- A selected playlist is always explicit. Deleted or missing selections fail safely and fall back to normal recommendations.
- Suggest presents a Home card and never starts or replaces playback. Prefer overrides Start Listening only inside the active window or during an explicit instant override.
- The local calendar window records start/end instants, time-zone identifier, version, and whether it was manually corrected. Start is inclusive and end is exclusive.
- Instant Active/Inactive overrides take precedence over the calendar and can be cleared to resume calendar behavior.
- Smart playlist rules persist per playlist with auto-grow off by default, explicit content categories, minimum confidence, weekly addition caps, and approval mode.
- Matching uses only optional server-provided `quran`, `quranTranslation`, or `religious` classifications. Language, title, genre, location, identity, and behavior are never classification inputs.
- Unknown categories and classifications below the configured confidence are ignored.
- Evaluation de-duplicates existing and pending tracks, applies deterministic ordering, observes the weekly cap, and uses optimistic playlist revisions.
- Approval proposals and completed additions carry local audit reasons. Added batches can be undone without deleting music from the library or device.
- Playlist summaries now accurately expose their auto-grow state.
- Home evaluates enabled rules locally and the settings screen evaluates immediately after saving a rule.
- The backend track model, editor, and v2 library payload now support allowlisted, confidence-clamped `content_classifications` metadata.
- Framework version advanced to `2.0.0-alpha.12`; the resource manifest and public API baselines were refreshed.

## Validation

- 88 Swift tests pass.
- Sprint fixtures cover calendar boundaries, time-zone metadata, manual correction, instant override, Off/Suggest/Prefer precedence, missing/deleted playlists, mixed languages, unknown and low-confidence classifications, auto-grow off, weekly caps, idempotent proposals, approval, audit, and undo.
- Generic iOS and macOS `UMusicApp` builds pass with code signing disabled.
- Architecture checks and public production symbol-graph baselines pass. SwiftPM still emits the known test-bundle symbol-graph warning after checking production graphs.
- Backend Python source compilation passes.
- The backend API regression test was added, but Django and pytest are not installed in the host Python and no Docker services are running, so the Django test and migration check could not execute locally.

## Boundaries and remaining gates

- No automatic calendar download is included. The window is versioned local data with manual correction; a future signed calendar data source can replace it without changing preference semantics.
- Classification is administrator-entered server metadata. No classifier or behavioral inference is introduced.
- Smart playlist membership is local in the v2 client today. A future server playlist sync must transmit final membership only and keep private local context/audit reasons on device.
- Audit storage is a compact local JSON document. Sprint 13's export work should define whether and how sanitized audit rows appear in research exports.
- Backend migration `0005_track_content_classifications` must be applied and the targeted Django test must pass before deployment. No Docker service was rebuilt, restarted, migrated, or deployed in this sprint run.

## Next sprint entry

Sprint 13 should implement bounded-memory Sanitized and Full exports, protected temporary-file lifecycle, schema manifests, optional encryption boundaries, the read-only macOS data inspector, and a reproducible trainer dataset with chronological splits and model-card documentation.
