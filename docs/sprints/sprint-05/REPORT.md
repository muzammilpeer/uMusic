# Sprint 05 report — deterministic learning engine v1

Status: complete

## Delivered

- Versioned `rules-v1` learning configuration with configurable signal weights,
  minimum evidence, and implicit half-life.
- Deterministic affinity rebuilds evaluated against the latest evidence time,
  producing a canonical SHA-256 evidence digest.
- Track, artist, ID3 genre, activity, named-place, and time-bucket affinities.
- Positive/negative evidence totals, sample counts, reason-code contributions,
  confidence, last observation, and algorithm version on every affinity.
- Ninety-day half-life for implicit evidence. Explicit preferences do not decay.
- Latest explicit track dislike/like is a hard `-1`/`+1` override; implicit
  behavior cannot overpower it.
- Three-observation minimum for contextual confidence. A single ambiguous late
  skip remains weak and low-confidence.
- Forgotten-place cutoffs exclude old place associations while preserving global
  and other contextual evidence.
- Safe behavior for missing genres/features; available target evidence is still
  learned without inventing a zero-valued feature.
- Synchronous rebuild/reset REST controls, an explainable dashboard, Celery owner
  and all-owner rebuild tasks, and a nightly scheduler entry.
- MP3 ingestion now stores ID3 genre values on tracks.

## Signal defaults

- Explicit like `+5.0`; explicit dislike `-8.0` with hard track override.
- Completion `+1.5`; replay `+2.5`.
- Early skip `-2.0`; late skip `-0.25`; queue removal `-0.75`.
- Scores use `tanh(net evidence / 5)` before explicit override.

## Verification

- Golden-data tests prove identical rebuilds produce identical rows and digest.
- Tests cover explicit dislike override, ambiguous skips, implicit decay, missing
  genres, activity isolation, and forgotten-place exclusion.
- Ruff, strict mypy, migrations, pytest, and branch coverage pass.

The project is ready for Sprint 06 playlist generation and sequencing.
