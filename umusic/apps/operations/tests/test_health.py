from unittest.mock import patch

import pytest
from django.test import Client

pytestmark = pytest.mark.django_db


def test_live_endpoint() -> None:
    response = Client().get("/health/live/")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    assert response.headers["Cache-Control"] == (
        "max-age=0, no-cache, no-store, must-revalidate, private"
    )


@patch("umusic.apps.operations.views._redis_check")
def test_ready_endpoint_reports_dependencies(redis_check: object) -> None:
    response = Client().get("/health/ready/")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "checks": {"database": {"status": "ok"}, "redis": {"status": "ok"}},
    }


@patch("umusic.apps.operations.views._redis_check", side_effect=ConnectionError)
def test_ready_endpoint_returns_503_without_exposing_details(redis_check: object) -> None:
    response = Client().get("/health/ready/")

    assert response.status_code == 503
    assert response.json() == {
        "status": "error",
        "checks": {
            "database": {"status": "ok"},
            "redis": {"status": "error", "type": "ConnectionError"},
        },
    }
