from collections.abc import Callable
from typing import Any

import redis
from django.conf import settings
from django.db import connections
from django.http import HttpResponse, JsonResponse
from django.views.decorators.cache import never_cache
from django.views.decorators.http import require_GET

Check = Callable[[], None]


def _database_check() -> None:
    with connections["default"].cursor() as cursor:
        cursor.execute("SELECT 1")
        cursor.fetchone()


def _redis_check() -> None:
    client = redis.Redis.from_url(settings.REDIS_URL, socket_connect_timeout=1, socket_timeout=1)
    try:
        client.ping()
    finally:
        client.close()  # type: ignore[no-untyped-call]


def _run_checks(checks: dict[str, Check]) -> tuple[dict[str, dict[str, str]], bool]:
    result: dict[str, dict[str, str]] = {}
    healthy = True
    for name, check in checks.items():
        try:
            check()
            result[name] = {"status": "ok"}
        except Exception as exc:
            healthy = False
            result[name] = {"status": "error", "type": type(exc).__name__}
    return result, healthy


@require_GET
@never_cache
def live(request: Any) -> JsonResponse:
    return JsonResponse({"status": "ok"})


@require_GET
@never_cache
def ready(request: Any) -> JsonResponse:
    checks, healthy = _run_checks({"database": _database_check, "redis": _redis_check})
    return JsonResponse(
        {"status": "ok" if healthy else "error", "checks": checks},
        status=200 if healthy else 503,
    )


@require_GET
@never_cache
def metrics(request: Any) -> HttpResponse:
    checks, healthy = _run_checks({"database": _database_check, "redis": _redis_check})
    lines = [
        "# HELP umusic_ready Whether required dependencies are ready.",
        "# TYPE umusic_ready gauge",
        f"umusic_ready {int(healthy)}",
    ]
    lines.extend(
        f'umusic_dependency_ready{{dependency="{name}"}} {int(value["status"] == "ok")}'
        for name, value in checks.items()
    )
    return HttpResponse("\n".join(lines) + "\n", content_type="text/plain; version=0.0.4")
