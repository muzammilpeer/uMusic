from django.urls import path

from umusic.apps.imports.adapter_views import (
    AdapterJobDetailView,
    AdapterListView,
    ConfirmCandidateView,
    FolderImportView,
    RemoteImportView,
    TasteImportView,
    YouTubeImportView,
)

urlpatterns = [
    path("", AdapterListView.as_view(), name="api-adapters"),
    path("folder/", FolderImportView.as_view(), name="api-folder-import"),
    path("taste/", TasteImportView.as_view(), name="api-taste-import"),
    path(
        "taste/<uuid:candidate_id>/confirm/",
        ConfirmCandidateView.as_view(),
        name="api-taste-confirm",
    ),
    path("youtube/", YouTubeImportView.as_view(), name="api-youtube-import"),
    path("remote/", RemoteImportView.as_view(), name="api-remote-import"),
    path("jobs/<uuid:job_id>/", AdapterJobDetailView.as_view(), name="api-adapter-job"),
]
