from django.urls import path

from umusic.apps.library.v2_api import LibraryChangesV2View

urlpatterns = [
    path("library/changes", LibraryChangesV2View.as_view(), name="api-v2-library-changes"),
]
