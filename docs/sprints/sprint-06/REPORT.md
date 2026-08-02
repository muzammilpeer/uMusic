# Sprint 06 report — context-aware playlist generation

Status: complete

## Delivered

- Hard eligibility filtering for active tracks with explicit track-dislike
  exclusion before scoring.
- Deterministic candidate ordering and seeded exploration.
- Global track, contextual activity/place, artist, familiarity, discovery,
  recently-played, energy-fit, duration-fit, and spacing signals.
- Activity-aware energy curves for warm-up, sustained work, gym recovery,
  focus/relax stability, and cooldown.
- Neutral energy fallback with an explicit `ENERGY_UNKNOWN` explanation when
  audio features are missing.
- Duration-aware greedy sequencing that targets the requested duration within an
  average track length when the eligible catalog is sufficient.
- Artist and album repetition penalties with tested adjacent-artist spacing.
- Cold-start selection that works before learning evidence exists.
- Immutable generated playlist versions with input digest, deterministic seed,
  model version, source-version lineage, selected scores, target energy, and
  reason-code explanations.
- Regenerate, replace-track, detail, and track-explanation REST APIs.
- Web generation form for activity, place, duration, energy, discovery, and
  seed, plus playable results and per-track replacement controls.
- Optional per-track energy storage for future audio-analysis adapters.

## Determinism

Candidates are sorted by stable track UUID before seeded jitter. Ties use the
same UUID ordering. Equal inputs, generator version, catalog/evidence state, and
seed therefore reproduce the same ordered track IDs and input digest.

## Verification

- Synthetic tests cover cycling, running, gym, focus, relax, and cold start.
- Tests prove seed reproducibility, requested-duration tolerance, hard dislike
  exclusion, adjacent artist spacing, missing energy handling, explanations,
  immutable replacement lineage, API workflows, and web generation.
- 62 tests pass; Ruff, strict mypy, migration checks, and 85% branch coverage
  pass.

The project is ready for Sprint 07 import adapters and taste acquisition.
