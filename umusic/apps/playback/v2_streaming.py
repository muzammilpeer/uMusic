from django.core import signing
from django.http import HttpRequest, HttpResponse
from django.http.response import HttpResponseBase

from umusic.apps.accounts.models import User
from umusic.apps.playback.streaming import stream_track
from umusic.apps.playback.v2_api import TICKET_SALT, TICKET_TTL_SECONDS


def stream_track_with_ticket(request: HttpRequest, track_id: str) -> HttpResponseBase:
    try:
        payload = signing.loads(
            request.GET.get("ticket", ""),
            salt=TICKET_SALT,
            max_age=TICKET_TTL_SECONDS,
        )
        if str(payload["track_id"]) != str(track_id):
            raise signing.BadSignature("Track mismatch")
        user = User.objects.get(pk=payload["user_id"], is_active=True)
    except (KeyError, TypeError, ValueError, User.DoesNotExist, signing.BadSignature):
        return HttpResponse(status=401)
    request.user = user
    return stream_track(request, track_id)
