from datetime import timedelta

from django.core import signing
from django.urls import reverse
from django.utils import timezone
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from umusic.apps.accounts.v2_api import _error
from umusic.apps.library.services import playable_tracks

TICKET_SALT = "umusic-v2-playback-ticket"
TICKET_TTL_SECONDS = 300
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
        requested = [str(value) for value in raw_ids]
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
        expires_at = timezone.now() + timedelta(seconds=TICKET_TTL_SECONDS)
        items = []
        for track_id in requested:
            track = tracks[track_id]
            ticket = signing.dumps(
                {"user_id": request.user.pk, "track_id": track_id},
                salt=TICKET_SALT,
                compress=True,
            )
            path = reverse("api-v2-track-stream", kwargs={"track_id": track_id})
            items.append(
                {
                    "track_id": track_id,
                    "url": request.build_absolute_uri(f"{path}?ticket={ticket}"),
                    "expires_at": expires_at,
                    "checksum": track.audio_file.checksum,
                    "bytes": track.audio_file.size_bytes,
                    "supports_ranges": True,
                }
            )
        return Response({"tickets": items})
