from django.urls import path

from umusic.apps.sync.views import (
    AcknowledgeView,
    ManifestView,
    SyncPlanCreateView,
    SyncPlanDetailView,
    download,
)

urlpatterns = [
    path("devices/<uuid:device_id>/sync-plans", SyncPlanCreateView.as_view()),
    path("sync-plans/<uuid:plan_id>", SyncPlanDetailView.as_view()),
    path("sync-plans/<uuid:plan_id>/manifest", ManifestView.as_view()),
    path("sync-plans/<uuid:plan_id>/acknowledge", AcknowledgeView.as_view()),
    path("sync-files/<str:token>", download, name="sync-download"),
]
