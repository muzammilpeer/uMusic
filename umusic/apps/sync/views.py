from datetime import timedelta
from urllib.parse import quote

from django.conf import settings
from django.core import signing
from django.http import HttpResponse, StreamingHttpResponse
from django.http.response import HttpResponseBase
from django.shortcuts import get_object_or_404
from django.urls import reverse
from django.utils import timezone
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from umusic.apps.accounts.models import Device
from umusic.apps.library.models import Track
from umusic.apps.library.storage import get_storage_for_backend
from umusic.apps.playback.streaming import _chunks, _range
from umusic.apps.recommendations.models import GeneratedPlaylist
from umusic.apps.sync.models import SyncPlan

# Long enough for a week of offline-first use. Links remain device-bound and
# are invalidated immediately when their device is revoked.
DOWNLOAD_MAX_AGE_SECONDS = settings.UMUSIC_SIGNED_URL_TTL_SECONDS


def signed_download_url(request: Request, *, track_id: object, device_id: object) -> str:
    """Return a temporary, device-bound URL AVPlayer can open without HTTP headers."""
    token = signing.dumps(
        {"track_id": str(track_id), "device_id": str(device_id)},
        salt="umusic-sync-download",
        compress=True,
    )
    return request.build_absolute_uri(
        reverse("sync-download", kwargs={"token": token})
    )


def manifest_entry(
    request: Request, track: Track, *, position: int, device_id: object
) -> dict[str, object]:
    audio = track.audio_file
    return {
        "track_id": str(track.id),
        "position": position,
        "title": track.title,
        "artist": {"id": str(track.artist_id), "name": track.artist.name},
        "album": (
            {"id": str(track.album_id), "title": track.album.title} if track.album else None
        ),
        "duration_ms": audio.duration_ms,
        "genres": track.genres,
        "energy": float(track.energy) if track.energy is not None else None,
        "stream_path": f"/api/v1/tracks/{track.id}/stream/",
        "size_bytes": audio.size_bytes,
        "sha256": audio.checksum,
        "metadata_version": int(track.updated_at.timestamp()),
        "artwork_checksum": track.artwork.checksum if track.artwork else None,
        "download_url": signed_download_url(
            request, track_id=track.id, device_id=device_id
        ),
        "download_expires_at": timezone.now() + timedelta(seconds=DOWNLOAD_MAX_AGE_SECONDS),
    }


def _plan_data(plan: SyncPlan) -> dict[str, object]:
    return {
        "id": str(plan.id),
        "device_id": str(plan.device_id),
        "playlist_id": str(plan.playlist_id),
        "manifest_version": plan.manifest_version,
        "acknowledged_at": plan.acknowledged_at,
        "created_at": plan.created_at,
    }


class SyncPlanCreateView(APIView):
    def post(self, request: Request, device_id: str) -> Response:
        # The Bearer token is authoritative. This also repairs clients that retained
        # an obsolete device UUID after a server restore or app reinstall.
        authenticated_device = request.auth
        if isinstance(authenticated_device, Device):
            device = authenticated_device
        else:
            device = get_object_or_404(
                Device, id=device_id, owner=request.user, revoked_at__isnull=True
            )
        playlist = get_object_or_404(
            GeneratedPlaylist, id=request.data.get("playlist_id"), owner=request.user
        )
        plan = SyncPlan.objects.create(owner=request.user, device=device, playlist=playlist)
        return Response(_plan_data(plan), status=201)


class SyncPlanDetailView(APIView):
    def get(self, request: Request, plan_id: str) -> Response:
        plan = get_object_or_404(SyncPlan, id=plan_id, owner=request.user)
        return Response(_plan_data(plan))


class ManifestView(APIView):
    def get(self, request: Request, plan_id: str) -> Response:
        plan = get_object_or_404(SyncPlan, id=plan_id, owner=request.user)
        entries = []
        for item in plan.playlist.items.select_related(
            "track__audio_file", "track__artwork", "track__artist", "track__album"
        ):
            entries.append(
                manifest_entry(
                    request, item.track, position=item.position, device_id=plan.device_id
                )
            )
        return Response(
            {
                "id": str(plan.id),
                "version": plan.manifest_version,
                "playlist_id": str(plan.playlist_id),
                "entries": entries,
            }
        )


class AcknowledgeView(APIView):
    def post(self, request: Request, plan_id: str) -> Response:
        plan = get_object_or_404(SyncPlan, id=plan_id, owner=request.user)
        plan.acknowledgement = {
            "downloaded_track_ids": request.data.get("downloaded_track_ids", []),
            "failed_track_ids": request.data.get("failed_track_ids", []),
        }
        plan.acknowledged_at = timezone.now()
        plan.save(update_fields=["acknowledgement", "acknowledged_at"])
        return Response(_plan_data(plan))


def download(request, token: str) -> HttpResponseBase:  # type: ignore[no-untyped-def]
    try:
        payload = signing.loads(
            token, salt="umusic-sync-download", max_age=DOWNLOAD_MAX_AGE_SECONDS
        )
        Device.objects.get(id=payload["device_id"], revoked_at__isnull=True)
        track = Track.objects.select_related("audio_file").get(
            id=payload["track_id"], is_active=True
        )
    except (
        signing.BadSignature,
        signing.SignatureExpired,
        Device.DoesNotExist,
        Track.DoesNotExist,
    ):
        return HttpResponse(status=401)
    audio = track.audio_file
    storage = get_storage_for_backend(audio.storage_backend)
    if not storage.exists(audio.object_key):
        return HttpResponse(status=404)
    headers = {
        "Content-Type": "audio/mpeg",
        "Content-Length": str(storage.size(audio.object_key)),
        "ETag": f'"{audio.checksum}"',
        "Cache-Control": "private, no-store",
        "Content-Disposition": (
            f"attachment; filename*=UTF-8''{quote(audio.original_filename)}"
        ),
    }
    size = storage.size(audio.object_key)
    start, end, status = 0, size - 1, 200
    range_header = request.headers.get("Range")
    if range_header:
        selected = _range(range_header, size)
        if selected is None:
            response = HttpResponse(status=416)
            response["Content-Range"] = f"bytes */{size}"
            return response
        start, end = selected
        status = 206
        headers["Content-Range"] = f"bytes {start}-{end}/{size}"
        headers["Content-Length"] = str(end - start + 1)
        headers["Accept-Ranges"] = "bytes"
    if settings.UMUSIC_USE_INTERNAL_REDIRECT and status == 200:
        response = HttpResponse(headers=headers)
        response["X-Accel-Redirect"] = (
            f"{settings.UMUSIC_INTERNAL_MEDIA_PREFIX.rstrip('/')}/{audio.object_key}"
        )
        return response
    return StreamingHttpResponse(
        _chunks(storage.open(audio.object_key), start, end - start + 1),
        status=status,
        headers=headers,
    )
