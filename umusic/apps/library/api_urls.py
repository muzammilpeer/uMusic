from django.urls import path

from umusic.apps.library.api_views import (
    AlbumCollectionView,
    ArtistCollectionView,
    TrackCollectionView,
    TrackDetailView,
)

urlpatterns = [
    path("tracks", TrackCollectionView.as_view(), name="api-track-list"),
    path("tracks/<uuid:track_id>", TrackDetailView.as_view(), name="api-track-detail"),
    path("search", TrackCollectionView.as_view(), name="api-search"),
    path("artists", ArtistCollectionView.as_view(), name="api-artist-list"),
    path("albums", AlbumCollectionView.as_view(), name="api-album-list"),
]
