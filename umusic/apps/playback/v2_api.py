from datetime import timedelta

from django.utils import timezone
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from umusic.apps.accounts.v2_api import _error
from umusic.apps.accounts.models import Device
from umusic.apps.library.services import playable_tracks
from umusic.apps.sync.views import DOWNLOAD_MAX_AGE_SECONDS, signed_download_url

# Retained for compatibility with already-issued v2 playback URLs and the
# legacy v2 stream endpoint. New tickets use the proven v1 device-bound route.
TICKET_SALT = "umusic-v2-playback-ticket"
TICKET_TTL_SECONDS = 60 * 60
MAX_TICKET_TRACKS = 100


class PlaybackTicketsV2View(APIView):
    def post(self, request: Request) -> Response:
        raw_ids = request.data.get("track_ids")
        if not isinstance(raw_ids, list) or not 1 <= len(raw_ids) <= MAX_TICKET_TRACKS:
            return _error(
                request,
                code="invalid_track_ids",
                message="Provide between 1 and 100 track identifiers.",
                status=400,
            )
        # Swift's JSONEncoder serializes UUID values with uppercase hex digits,
        # while Django's UUID string representation is lowercase. Normalize at
        # the API boundary before using identifiers as dictionary keys.
        requested = [str(value).lower() for value in raw_ids]
        tracks = {
            str(track.id): track
            for track in playable_tracks(request.user)
            .select_related("audio_file")
            .filter(id__in=requested)
        }
        if len(tracks) != len(set(requested)):
            return _error(
                request,
                code="media_unavailable",
                message="One or more tracks are unavailable.",
                status=404,
            )
        device = request.auth if isinstance(request.auth, Device) else None
        if device is None:
            return _error(
                request,
                code="device_required",
                message="A registered device is required for media access.",
                status=403,
            )
        expires_at = timezone.now() + timedelta(seconds=DOWNLOAD_MAX_AGE_SECONDS)
        items = []
        for track_id in requested:
            track = tracks[track_id]
            items.append(
                {
                    "track_id": track_id,
                    "url": signed_download_url(
                        request, track_id=track_id, device_id=device.id
                    ),
                    "expires_at": expires_at,
                    "checksum": track.audio_file.checksum,
                    "bytes": track.audio_file.size_bytes,
                    "supports_ranges": True,
                }
            )
        return Response({"tickets": items})
