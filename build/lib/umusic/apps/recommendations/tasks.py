from celery import shared_task

from umusic.apps.accounts.models import User
from umusic.apps.recommendations.services import rebuild_affinities


@shared_task
def rebuild_owner_learning(owner_id: int) -> str:
    owner = User.objects.get(id=owner_id)
    return str(rebuild_affinities(owner).id)


@shared_task
def rebuild_all_learning() -> int:
    count = 0
    for owner in User.objects.filter(is_active=True).iterator():
        rebuild_affinities(owner)
        count += 1
    return count
