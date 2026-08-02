# ADR 0001 — Modular Django monolith

- Status: accepted
- Date: 2026-08-02

## Decision

Build uMusic as one Django deployment divided into explicit domain applications.
Use Celery for asynchronous work, PostgreSQL for durable relational state, Redis
for task transport/cache, and a replaceable media-storage boundary.

## Consequences

Deployment, migrations, authentication, and transactions remain understandable
for a self-hosted project. Domain packages must avoid circular ownership and can
be extracted only if measured operational needs justify it.

