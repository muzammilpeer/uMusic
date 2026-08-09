from celery import shared_task

from umusic.apps.imports.models import AdapterJob
from umusic.apps.imports.remote_services import run_remote_import


@shared_task
def process_remote_import(job_id: str) -> str:
    job = AdapterJob.objects.select_related("owner").get(id=job_id)
    return run_remote_import(job).status
