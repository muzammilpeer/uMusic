# ADR 0002: Core Data Persistence

- Status: Accepted
- Date: 2026-08-09

## Decision

Use Core Data with separate Catalog, User, and Telemetry persistent stores, background contexts, versioned models, and explicit migrations.

## Rationale

Core Data provides mature migration, batch operation, store inspection/copy, background-context, and large-dataset tooling across the chosen platforms. Domain and framework APIs expose value types, never managed objects.

## Consequences

More explicit schema/context code is accepted in exchange for predictable migration/export behavior. Destructive model resets are forbidden as a migration strategy.

