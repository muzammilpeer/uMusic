from django.urls import path

from umusic.apps.contexts.views import (
    ActivityCollectionView,
    ContextSnapshotView,
    ForgetPlaceView,
    GeofenceCollectionView,
    GeofenceDetailView,
)

urlpatterns = [
    path("activities/", ActivityCollectionView.as_view(), name="api-activities"),
    path("geofences/", GeofenceCollectionView.as_view(), name="api-geofences"),
    path("geofences/<uuid:place_id>/", GeofenceDetailView.as_view(), name="api-geofence"),
    path(
        "geofences/<uuid:place_id>/forget-learning/",
        ForgetPlaceView.as_view(),
        name="api-geofence-forget",
    ),
    path("snapshots/", ContextSnapshotView.as_view(), name="api-context-snapshots"),
]
