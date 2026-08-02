from django.urls import path

from umusic.apps.playlists.views import PlaylistCollectionView, PlaylistDetailView

urlpatterns = [
    path("", PlaylistCollectionView.as_view(), name="api-playlists"),
    path("<uuid:playlist_id>/", PlaylistDetailView.as_view(), name="api-playlist"),
]
