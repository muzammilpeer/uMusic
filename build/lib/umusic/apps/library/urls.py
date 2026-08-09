from django.urls import path

from umusic.apps.library import views

app_name = "library"

urlpatterns = [
    path("", views.index, name="index"),
    path("tracks/<uuid:track_id>/", views.track_detail, name="track-detail"),
    path("artists/<uuid:artist_id>/", views.artist_detail, name="artist-detail"),
    path("albums/<uuid:album_id>/", views.album_detail, name="album-detail"),
    path("imports/", views.imports, name="imports"),
    path("imports/<uuid:job_id>/", views.import_detail, name="import-detail"),
    path("events/", views.event_history, name="events"),
    path("session/setup/", views.context_setup, name="context-setup"),
    path("places/", views.places, name="places"),
    path("learning/", views.learning, name="learning"),
    path("generated/", views.generated_playlists, name="generated-playlists"),
    path("generated/<uuid:playlist_id>/", views.generated_detail, name="generated-detail"),
    path("adapters/", views.adapter_inbox, name="adapter-inbox"),
    path("operations/", views.operations_dashboard, name="operations"),
    path("devices/", views.devices, name="devices"),
    path("evaluation/", views.evaluation, name="evaluation"),
    path("privacy/", views.privacy, name="privacy"),
    path("privacy/export/", views.privacy_export, name="privacy-export"),
]
