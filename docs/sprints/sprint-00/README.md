# Sprint 00 — Repository and engineering foundation

**Status:** Complete — see [REPORT.md](REPORT.md).

## Goal

Create a repeatable Django development environment and the modular-monolith
skeleton on which all later sprints depend.

## Deliverables

- Django project and domain app packages.
- PostgreSQL, Redis, Celery worker, and scheduler wiring.
- Docker Compose development environment.
- Environment-based settings and `.env.example`.
- Ruff, formatting, typing, pytest, coverage, and pre-commit.
- CI for linting, tests, migrations, and dependency checks.
- Dependency-aware health endpoint and developer setup guide.

## Exit criteria

- A clean checkout starts using documented commands.
- Health checks confirm database and Redis connectivity.
- An empty database migrates successfully.
- All automated checks pass.

## Start

Use [PROMPT.md](PROMPT.md).
