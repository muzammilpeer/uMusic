.PHONY: bootstrap check format lint migrate migrations owner run test typecheck up down logs shell

bootstrap:
	python3.13 -m venv .venv
	.venv/bin/pip install --upgrade pip
	.venv/bin/pip install -e '.[dev]'

check: lint typecheck test migrations

format:
	.venv/bin/ruff check --fix .
	.venv/bin/ruff format .

lint:
	.venv/bin/ruff check .
	.venv/bin/ruff format --check .

typecheck:
	.venv/bin/mypy config umusic

test:
	.venv/bin/coverage run -m pytest
	.venv/bin/coverage report

migrate:
	.venv/bin/python manage.py migrate

owner:
	.venv/bin/python manage.py bootstrap_owner

migrations:
	.venv/bin/python manage.py makemigrations --check --dry-run

run:
	.venv/bin/python manage.py runserver

up:
	docker compose up --build

down:
	docker compose down

logs:
	docker compose logs --tail=200

shell:
	docker compose exec web python manage.py shell
