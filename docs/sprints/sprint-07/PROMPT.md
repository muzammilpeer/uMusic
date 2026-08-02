# Sprint 07 implementation prompt

```text
Implement Sprint 07 of uMusic after verifying Sprint 06. Create an audited,
feature-flagged adapter interface and a configured-root MP3 folder importer. Add
authorized taste/export metadata import with a confirmation inbox for uncertain
matches.

Then add an OPTIONAL private YouTube audio adapter using a maintained Python
library or controlled subprocess wrapper. It must be disabled by default, require
operator attestation that each source is authorized, record provenance, enforce
rate/concurrency/size limits, and pass output through the standard MP3 pipeline.
Do not implement credentials, DRM, paywall, age-gate, regional, or access-control
bypasses. Treat taste import and audio acquisition as separate permissions/jobs.

Test feature flags, root traversal, matching confidence, audit data, failures,
limits, and ingestion reuse. Run all checks and report Sprint 08 readiness.
```

