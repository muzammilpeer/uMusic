from django.urls import path

from umusic.apps.imports.views import ImportJobView, UploadView

urlpatterns = [
    path("uploads/", UploadView.as_view(), name="api-import-upload"),
    path("<uuid:job_id>/", ImportJobView.as_view(), name="api-import-detail"),
]
