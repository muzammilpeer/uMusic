from django.urls import path

from umusic.apps.playback.streaming import stream_track

urlpatterns = [path("<uuid:track_id>/stream/", stream_track, name="api-track-stream")]
