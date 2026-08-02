# Definition of done

A story or sprint is done only when all applicable conditions below are met.

## Behavior

- Acceptance criteria are demonstrated through the user-facing path.
- Empty, loading, error, retry, and permission-denied states are handled.
- The feature remains useful when optional location or HealthKit access is denied.
- Background jobs are observable, idempotent where required, and safely retryable.

## Quality

- Unit and integration tests cover the happy path and important failures.
- Streaming, upload, authentication, event ingestion, and sync receive end-to-end
  tests appropriate to their risk.
- Storage contract tests pass against local and mounted-filesystem implementations.
- Queue exhaustion is tested online, during network loss, and fully offline.
- Database migrations work against an empty database and an upgraded fixture.
- Formatting, linting, type checks, tests, and documentation checks pass.
- Performance-sensitive queries are measured and avoid unbounded N+1 behavior.

## Security and privacy

- Authorization is checked at the object and file-delivery layers.
- Inputs are content-validated and size-limited.
- Secrets, tokens, signed URLs, and precise location are absent from logs.
- Location collection is minimal, permission-based, and documented.
- Delete/forget behavior is tested for personal and learned data.
- Import adapters cannot escape configured roots or bypass access controls.

## Recommendations

- Inputs, feature configuration, random seed, and model version are recorded.
- Outputs include reason codes.
- Explicit dislikes and hard exclusions cannot be overridden by learned scores.
- Deterministic fallback behavior exists when learning data or workers are absent.
- Evaluation metrics are updated when ranking behavior changes.

## Operations

- Configuration changes are reflected in `.env.example` and deployment docs.
- Health checks and useful diagnostics cover new dependencies.
- Backup implications are documented.
- Upgrade and rollback considerations are noted.
- No deployment depends on an undocumented manual database or filesystem change.

## Handoff

The sprint report states:

- delivered behavior;
- important design decisions;
- migrations and configuration changes;
- tests/checks run and their results;
- known limitations or deferred work;
- exact next sprint entry conditions.
