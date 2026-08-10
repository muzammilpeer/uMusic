from django.urls import path

from umusic.apps.playback.v2_api import PlaybackTicketsV2View
from umusic.apps.playback.v2_streaming import stream_track_with_ticket

urlpatterns = [
    path("media/playback-tickets", PlaybackTicketsV2View.as_view(), name="api-v2-playback-tickets"),
    path(
        "media/tracks/<uuid:track_id>/stream", stream_track_with_ticket, name="api-v2-track-stream"
    ),
]
