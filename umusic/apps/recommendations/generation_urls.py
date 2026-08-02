from django.urls import path

from umusic.apps.recommendations.generation_views import (
    GeneratedPlaylistDetailView,
    GeneratePlaylistView,
    RegeneratePlaylistView,
    ReplaceTrackView,
    TrackExplanationView,
)

urlpatterns = [
    path("session-playlist/", GeneratePlaylistView.as_view(), name="api-generate-playlist"),
    path(
        "generated-playlists/<uuid:playlist_id>/",
        GeneratedPlaylistDetailView.as_view(),
        name="api-generated-playlist",
    ),
    path(
        "generated-playlists/<uuid:playlist_id>/regenerate/",
        RegeneratePlaylistView.as_view(),
        name="api-regenerate-playlist",
    ),
    path(
        "generated-playlists/<uuid:playlist_id>/replace-track/",
        ReplaceTrackView.as_view(),
        name="api-replace-generated-track",
    ),
    path(
        "tracks/<uuid:track_id>/explanation/",
        TrackExplanationView.as_view(),
        name="api-track-explanation",
    ),
]
