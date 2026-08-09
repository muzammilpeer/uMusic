from django.urls import path

from umusic.apps.playlists import web_views

urlpatterns = [
    path("", web_views.sharing_home, name="playlist-sharing"),
    path("<uuid:playlist_id>/", web_views.sharing_detail, name="playlist-sharing-detail"),
    path(
        "invitations/<uuid:invitation_id>/respond/",
        web_views.invitation_response,
        name="playlist-sharing-invitation-response",
    ),
]
