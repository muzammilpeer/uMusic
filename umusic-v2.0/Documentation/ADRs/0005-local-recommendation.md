# ADR 0005: Local Recommendation Runtime

- Status: Accepted
- Date: 2026-08-09

## Decision

Use deterministic heuristics first and a bounded Core ML ranker later, always with policy reranking and fallback. LLMs may analyze explicitly exported redacted data during development but do not participate in the playback loop.

## Consequences

Recommendations remain fast, offline, testable, and explainable. Model/feature versions and reason codes accompany each result. No personal profile upload endpoint is part of v2.0.

