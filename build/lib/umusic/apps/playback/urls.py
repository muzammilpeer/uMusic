from django.urls import path

from umusic.apps.playback.views import (
    ContinuationView,
    QueueView,
    SessionCollectionView,
    SessionDetailView,
)

urlpatterns = [
    path("sessions/", SessionCollectionView.as_view(), name="api-playback-sessions"),
    path("sessions/<uuid:session_id>/", SessionDetailView.as_view(), name="api-playback-session"),
    path("sessions/<uuid:session_id>/queue/", QueueView.as_view(), name="api-playback-queue"),
    path(
        "sessions/<uuid:session_id>/continuations/",
        ContinuationView.as_view(),
        name="api-playback-continuation",
    ),
]
