# Data and learning model

## Principle

Treat recommendation as an observable product feature, not a mysterious model.
Begin with deterministic ranking, collect trustworthy events, evaluate it, and
only then introduce statistical models.

## Core records

### Track

- title, artist, album, album artist;
- duration, year, track/disc number;
- genres and user tags;
- bitrate and sample rate;
- checksum and storage key;
- optional musical features;
- availability and explicit-content state.

### Listening event

Use an append-only event table. Required fields include:

- unique client event ID for idempotency;
- user, device, track, session, and queue IDs;
- event type and client timestamp;
- server receipt timestamp;
- position and track duration;
- context snapshot ID;
- recommendation/model version;
- offline flag.

Event types initially include `started`, `progress`, `paused`, `resumed`,
`seeked`, `completed`, `skipped`, `liked`, `disliked`, `replayed`, and
`queue_removed`.

### Context snapshot

- activity ID;
- workout phase;
- target energy;
- geofence ID, never a coordinate by default;
- time bucket and weekday/weekend;
- planned session duration;
- discovery setting;
- optional device-reported motion/speed bucket.

### Affinity

Materialized affinities relate a user or context to a track, artist, genre, tag,
or feature bucket. Store positive evidence, negative evidence, confidence,
sample count, last observation, and algorithm version.

## Signal interpretation

Suggested starting weights:

| Signal | Base value |
|---|---:|
| Explicit like | +5.0 |
| Explicit dislike | -8.0 |
| Completed at least 90% | +1.5 |
| Replayed within session | +2.5 |
| Skipped in first 20% | -2.0 |
| Skipped after 80% | -0.25 |
| Added to playlist | +3.0 |
| Removed from queue | -0.75 |

Weights must be configurable and versioned. Apply time decay to implicit signals
but decay explicit preferences slowly. Require multiple observations before a
context-specific conclusion dominates global taste.

## Recommendation stages

1. **Eligibility:** available file, not disliked/blocked, valid duration, and
   compatible with any hard activity rules.
2. **Candidate generation:** global favorites, context favorites, similar tags,
   under-explored library, recent positive artists, and playlist seeds.
3. **Scoring:** taste, context affinity, energy fit, familiarity/discovery target,
   novelty, and confidence.
4. **Penalties:** recent play, repeated artist/album, recent skips, excessive
   explicit content when filtered, and duration mismatch.
5. **Sequencing:** smooth energy curve, artist spacing, phase transitions, and
   total-duration fit.
6. **Explanation:** persist top positive and negative reason codes.

Example score:

```text
score =
  0.30 * global_taste
+ 0.25 * activity_affinity
+ 0.10 * geofence_affinity
+ 0.10 * time_affinity
+ 0.10 * energy_fit
+ 0.10 * discovery_fit
+ 0.05 * freshness
- repetition_penalty
- recent_skip_penalty
```

If a feature is unknown, renormalize available weights rather than treating the
feature as zero preference.

## Cold start

Until enough behavior exists:

- ask the user to select favorite artists/tracks;
- import taste metadata from authorized exports or playlists;
- use existing folder/playlist organization;
- allow activity-specific seed playlists;
- mix 80% seeded/familiar tracks with 20% exploration by default.

External taste signals should have lower confidence than behavior observed inside
uMusic. Matching uses normalized artist/title first, then duration and album when
available. Never silently merge an uncertain match.

## Activity intelligence

Initial activity presets:

- cycling: gradual warm-up, sustained energy, recovery dips, cooldown;
- running: stronger tempo consistency and smaller energy jumps;
- gym: high energy with configurable rest-period behavior;
- focus: low interruption, long stable blocks, lyrics preference setting;
- relax: low energy and higher familiarity;
- commute/walk: balanced discovery;
- custom: user-defined curve and filters.

Do not claim that a song medically improves performance. The model predicts
personal preference and completion under a context.

## Geofence learning

The user creates named places with center and radius. Exact coordinates are used
only to resolve entry/exit. Listening events reference the opaque geofence ID.
Users can manually choose a place from the web, enabling learning before the
iPhone location feature exists.

Useful controls:

- “Prefer this track here.”
- “Do not play this track here.”
- “Use this playlist as a seed here.”
- “Forget learning for this place.”

## Evaluation

Maintain an offline evaluation job and a product dashboard:

- completion rate by activity;
- early-skip rate;
- explicit approval rate;
- artist and album diversity;
- catalog coverage;
- recommendation latency;
- percentage of tracks with explanations;
- performance by model version;
- exploration acceptance rate.

Version every scoring configuration. A generated playlist retains its version so
results can be compared rather than overwritten by later learning.

## When to add ML

After at least several thousand reliable events, evaluate:

1. logistic regression predicting completion;
2. gradient-boosted ranking using contextual features;
3. contextual bandit for controlled exploration;
4. audio embeddings only if metadata behavior cannot deliver enough diversity.

Keep hard safety/preferences and sequencing outside the learned model. Always
retain a deterministic fallback.

