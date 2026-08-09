from django.urls import path

from umusic.apps.playlists.views import (
    PlaylistCollectionView,
    PlaylistDetailView,
    PlaylistInvitationCollectionView,
    PlaylistInvitationResponseView,
    PlaylistLeaveView,
    PlaylistMemberCollectionView,
    PlaylistMemberDetailView,
    PlaylistTransferView,
    SaveSharedTrackView,
)

urlpatterns = [
    path("", PlaylistCollectionView.as_view(), name="api-playlists"),
    path("<uuid:playlist_id>/", PlaylistDetailView.as_view(), name="api-playlist"),
    path(
        "<uuid:playlist_id>/invitations/",
        PlaylistInvitationCollectionView.as_view(),
        name="api-playlist-invite",
    ),
    path(
        "invitations/", PlaylistInvitationCollectionView.as_view(),
        name="api-playlist-invitations",
    ),
    path(
        "invitations/<uuid:invitation_id>/respond/",
        PlaylistInvitationResponseView.as_view(),
        name="api-playlist-invitation-respond",
    ),
    path(
        "<uuid:playlist_id>/members/", PlaylistMemberCollectionView.as_view(),
        name="api-playlist-members",
    ),
    path(
        "<uuid:playlist_id>/members/<int:user_id>/",
        PlaylistMemberDetailView.as_view(),
        name="api-playlist-member",
    ),
    path(
        "<uuid:playlist_id>/leave/", PlaylistLeaveView.as_view(),
        name="api-playlist-leave",
    ),
    path(
        "<uuid:playlist_id>/transfer/", PlaylistTransferView.as_view(),
        name="api-playlist-transfer",
    ),
    path(
        "<uuid:playlist_id>/tracks/<uuid:track_id>/save/",
        SaveSharedTrackView.as_view(),
        name="api-playlist-track-save",
    ),
]
