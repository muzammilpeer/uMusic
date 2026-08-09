from pathlib import Path

import pytest
from django.conf import settings
from django.core.management import CommandError, call_command
from django.test import Client
from django.urls import reverse

from umusic.apps.accounts.models import User
from umusic.apps.operations.models import OperationalJob
from umusic.apps.operations.tasks import refresh_owner_playlists


@pytest.mark.django_db
def test_refresh_is_observable_and_idempotent() -> None:
    owner = User.objects.create_user(username="operator")
    first = refresh_owner_playlists(owner, "daily:operator:2026-08-02")
    second = refresh_owner_playlists(owner, "daily:operator:2026-08-02")
    assert first.id == second.id
    assert second.status == "completed"
    assert OperationalJob.objects.count() == 1


@pytest.mark.django_db
def test_backup_creates_database_and_media_manifest(tmp_path: Path) -> None:
    User.objects.create_user(username="backup-owner")
    target = tmp_path / "backup"
    call_command("backup_umusic", output=str(target))
    assert (target / "database.json").stat().st_size > 0
    assert (target / "media-manifest.json").read_text().startswith("[")
    with pytest.raises(CommandError, match="--confirm"):
        call_command("restore_umusic", input=str(target))
    call_command("flush", interactive=False)
    call_command("restore_umusic", input=str(target), confirm=True)
    assert User.objects.filter(username="backup-owner").exists()


@pytest.mark.django_db
def test_operations_dashboard_and_manual_refresh(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    class FakeRedis:
        def llen(self, _queue: str) -> int:
            return 3

        def close(self) -> None:
            pass

    monkeypatch.setattr(
        "umusic.apps.library.views.redis.Redis.from_url",
        lambda _url: FakeRedis(),
    )
    monkeypatch.setattr(settings, "MEDIA_ROOT", tmp_path / "media")
    owner = User.objects.create_user(username="dashboard-owner", password="test-password")
    client = Client()
    assert client.login(username=owner.username, password="test-password")

    response = client.get(reverse("library:operations"))
    assert response.status_code == 200
    assert response.context["queue_depth"] == 3

    response = client.post(reverse("library:operations"), data={})
    assert response.status_code == 302
    job = OperationalJob.objects.get(owner=owner)
    assert job.status == "completed"

    job.status = "failed"
    job.save(update_fields=["status"])
    response = client.post(reverse("library:operations"), data={"job_id": str(job.id)})
    assert response.status_code == 302
    job.refresh_from_db()
    assert job.status == "completed"


@pytest.mark.django_db
def test_catalog_benchmark_can_generate_a_fixture(capsys: pytest.CaptureFixture[str]) -> None:
    call_command("benchmark_catalog", generate=True, size=10, batch_size=4, max_ms=10_000)
    output = capsys.readouterr().out
    assert "generated=10/10" in output
    assert "active_tracks=10" in output
