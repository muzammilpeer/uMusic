# Contributing

## Prerequisites

- Docker with Compose for the canonical environment.
- Python 3.13 for optional local development.

## First run with Docker

```bash
cp .env.example .env
docker compose up --build
```

Change `DJANGO_SECRET_KEY` before using the server beyond local development. The
web server listens on `http://localhost:8000`; readiness is available at
`/health/ready/` and liveness at `/health/live/`.

To access development uMusic from another device on the LAN, add the server IP
to `DJANGO_ALLOWED_HOSTS` and its complete origin, including scheme and port, to
`DJANGO_CSRF_TRUSTED_ORIGINS`. The example configuration includes
`192.168.1.67:8000` for this server; update it if the server address changes.

## Local development

```bash
make bootstrap
make migrate
make check
make run
```

Local settings use SQLite unless `DATABASE_URL` is set. Redis is required for a
successful readiness response and for Celery, but unit tests mock its health
probe. Docker uses PostgreSQL and Redis.

## Create the first owner

Set credentials without putting a password in shell history, then run the
idempotent bootstrap command:

```bash
export UMUSIC_OWNER_USERNAME=owner
export UMUSIC_OWNER_EMAIL=owner@example.test
export UMUSIC_OWNER_PASSWORD='replace-with-a-long-password'
docker compose exec web python manage.py bootstrap_owner
```

## Change workflow

1. Read the active sprint folder under `docs/sprints/`.
2. Preserve unrelated work and never commit `.env` or media.
3. Add migrations and tests with behavior changes.
4. Run `make check` or the equivalent container commands.
5. Update contracts and operational documentation.
