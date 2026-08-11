from celery import shared_task

from umusic.apps.library.audio_analysis import analyze_track
from umusic.apps.library.mert_analysis import configured_provider
from umusic.apps.library.models import Track, TrackAnalysis


@shared_task(bind=True, autoretry_for=(OSError,), retry_backoff=True, max_retries=3)
def analyze_track_audio(self, track_id: str) -> str:
    track = Track.objects.select_related("audio_file").get(pk=track_id)
    analysis, _ = TrackAnalysis.objects.get_or_create(
        track=track,
        defaults={
            "source_checksum": track.audio_file.checksum.lower(),
            "provider": "deterministic",
            "model_version": "checksum-fixture-1",
        },
    )
    analysis.status = TrackAnalysis.Status.RUNNING
    analysis.save(update_fields=["status", "updated_at"])
    try:
        return str(analyze_track(track.id, provider=configured_provider()).track_id)
    except OSError:
        analysis.status = TrackAnalysis.Status.RETRYABLE_FAILURE
        analysis.error_code = "provider_io"
        analysis.save(update_fields=["status", "error_code", "updated_at"])
        raise
    except Exception:
        analysis.status = TrackAnalysis.Status.PERMANENT_FAILURE
        analysis.error_code = "analysis_failed"
        analysis.save(update_fields=["status", "error_code", "updated_at"])
        raise
