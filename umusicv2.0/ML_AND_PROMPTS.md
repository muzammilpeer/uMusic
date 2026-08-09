# Local Learning, Ranking, and Prompt Pack

## Recommendation design

Use a layered system, not an LLM in the playback loop.

1. **Eligibility:** playable, policy-compatible, not unavailable, not recently overplayed.
2. **Candidate generation:** recent affinity, activity/context affinity, similar metadata/embedding, playlist/co-listen transitions, exploration pool, and manually requested seed.
3. **Ranking:** on-device linear/GBDT/small neural Core ML model over bounded numeric features.
4. **Policy rerank:** diversity, era/language/genre balance, repetition limits, queue coherence, explicit/Ramadan preference, and manual queue priority.
5. **Explanation:** deterministic reason codes, never free-form model speculation.

## Cold start

- If the user provides seed preferences, build a diversified queue from them with 20–30% exploration.
- Otherwise use catalog-wide diversity: recent additions, broadly representative genres/languages/eras, and server-provided non-personal popularity only if available.
- Avoid consecutive same-artist tracks and cap album/genre concentration.
- Treat the first 20–50 meaningful observations as calibration; favor exploration and explicit actions.

## Feature vector

Track: genre/tag multi-hot or embedding, language, release year/decade, BPM, pace, energy, valence, speech/instrumental scores, duration, recency, offline availability.  
Context: cyclical hour/day encodings, weekend, activity/source/confidence, coarse place, route category, energy policy, network class, optional calendar preference.  
User history: decayed track/artist/album/genre/language/era affinity, exposure, completion, skip/replay/favorite rates, time since last play, play count.  
Sequence: previous-track similarity, artist/album repetition, tempo/energy transition, queue origin, recent diversity.

Do not include username, precise coordinates, raw HealthKit samples, server URL, or accessory identifiers.

## Training target

Create a weighted implicit-reward label, initially rule based:

```text
+4 favorite or explicit add-to-playlist
+3 replay / manual play after recommendation
+2 natural completion above 90%
+1 listened above 60%
 0 interruption/error/unknown exposure
-1 skip after 10–40%
-3 deliberate skip before 10 seconds when audible
-4 explicit dislike
```

Normalize by track duration and exclude technical failures. Use exposure-aware negative sampling. Split evaluation chronologically by session to prevent leakage.

## Compact learned records

Maintain exponentially decayed sufficient statistics rather than retaining all history forever:

```json
{
  "feature_key": "activity:running|genre:electronic|hour:morning",
  "schema_version": 1,
  "exposures": 42,
  "positive_weight": 51.5,
  "negative_weight": 8.0,
  "mean_completion": 0.78,
  "decayed_score": 0.64,
  "confidence": 0.71,
  "last_updated": "2026-08-09T08:42:11Z"
}
```

Use hierarchical backoff: exact context → activity+time → activity → global affinity. This ensures sparse contexts still produce useful results.

## Model lifecycle

- Begin with transparent heuristic scoring and log shadow features.
- Train offline using user-exported, consented datasets on the developer Mac.
- Convert to Core ML; sign model and feature manifest; bundle a fallback model.
- App validates signature, schema, OS/hardware support, and a canary inference before activation.
- Record version with every recommendation; allow rollback and disable remotely only through non-personal configuration.
- On-device incremental learning, if added, updates a small calibration layer or affinity table—not an unconstrained LLM.

## Evaluation

- Offline: NDCG@10, Recall@25, mean reciprocal rank, coverage, novelty, artist/genre diversity, calibration by activity/time, and cold-start results.
- Online/local: skip-before-10s rate, completion, manual intervention, queue edits, repeated-artist annoyance, startup latency, battery, and inference failures.
- Compare against recent-history and shuffled-diversity baselines.
- Audit performance by language and catalog sparsity without exporting identity.

## Prompt pack

These prompts are for development-time analysis of explicitly exported, redacted data. They are not runtime product dependencies.

### 1. Metadata quality auditor

```text
System: You audit a private music catalog. Never invent missing metadata. Return JSON only.
User: Given the supplied track rows and schema, identify invalid duration/year/language/genre values, duplicate audio identities, inconsistent artist/album naming, and missing fields that block ranking. For each issue return track_id, field, severity, evidence, and a non-destructive remediation. Do not infer sensitive user attributes.
```

### 2. Dataset profiler

```text
System: You are a privacy-preserving ML data analyst. Work only from aggregate/export fields supplied. Do not infer identity, religion, health status, or precise location.
User: Profile observation coverage by activity, time bucket, language, era, genre, and route category. Report sparsity, class imbalance, likely leakage, ambiguous labels, and fields that should be excluded. Recommend train/validation/test splits by chronological listening session. Return Markdown plus a machine-readable JSON summary.
```

### 3. Ranking experiment designer

```text
System: You design reproducible on-device recommendation experiments for iOS. Respect the feature schema and latency/energy budgets.
User: Propose three models from simplest to most capable for the attached aggregate schema. For each specify features, target, negative sampling, training method, Core ML conversion, expected model size, inference budget, failure fallback, and evaluation against heuristic baselines. Do not propose cloud inference.
```

### 4. Model-card generator

```text
System: Produce an honest model card from supplied measurements only. Mark unknowns explicitly.
User: Create a model card covering purpose, non-goals, data provenance/consent, feature exclusions, temporal split, metrics, language/activity coverage, privacy risks, battery/latency, known limitations, rollback conditions, and version compatibility.
```

### 5. Sprint implementation prompt template

```text
Implement uMusic 2.0 Sprint <N> from umusicv2.0/SPRINTS.md.
Read the uMusic skill and only the references it routes to. Treat v1 as read-only unless the sprint explicitly defines a migration adapter. Work inside umusicv2.0. Preserve user data and unrelated edits. Use clean architecture boundaries from ARCHITECTURE.md, API contracts from API_CONTRACT.md, and privacy constraints from DATA_AND_PRIVACY.md. Add tests for every acceptance criterion, run proportional validation, and report changed files, decisions, limitations, and measured results.
```

### 6. Telemetry review prompt

```text
Review this proposed event/schema change against umusicv2.0/DATA_AND_PRIVACY.md. Identify whether each field is necessary for a named recommendation feature, its sensitivity, retention, aggregation path, export behavior, indexing/storage cost, and permission requirement. Reject fields without a concrete use. Return a migration-safe revised schema and tests; never add raw continuous sensor samples.
```

