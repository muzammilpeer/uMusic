from datetime import date

from celery import shared_task
from django.utils import timezone

from umusic.apps.accounts.models import User
from umusic.apps.operations.models import OperationalJob
from umusic.apps.recommendations.generator import regenerate_playlist
from umusic.apps.recommendations.models import GeneratedPlaylist


def refresh_owner_playlists(owner: User, key: str) -> OperationalJob:
    existing = OperationalJob.objects.filter(idempotency_key=key).first()
    if existing and existing.status == "completed":
        return existing
    job = existing or OperationalJob.objects.create(
        owner=owner, kind="smart_playlist_refresh", idempotency_key=key
    )
    if existing:
        job.status, job.error, job.attempts = "running", "", job.attempts + 1
        job.save()
    try:
        latest: dict[str, GeneratedPlaylist] = {}
        for playlist in GeneratedPlaylist.objects.filter(owner=owner).select_related(
            "context_snapshot"
        ):
            latest.setdefault(playlist.activity_kind, playlist)
        versions = [regenerate_playlist(owner, item) for item in latest.values()]
        job.status, job.result = "completed", {"versions_created": len(versions)}
    except Exception as error:
        job.status, job.error = "failed", str(error)
    job.completed_at = timezone.now()
    job.save()
    return job


@shared_task
def scheduled_smart_playlist_refresh() -> int:
    count = 0
    for owner in User.objects.filter(is_active=True).iterator():
        refresh_owner_playlists(owner, f"scheduled-refresh:{owner.id}:{date.today().isoformat()}")
        count += 1
    return count
