from django.urls import path

from umusic.apps.events.views import EventBatchView, EventListView

urlpatterns = [
    path("", EventListView.as_view(), name="api-events"),
    path("batch/", EventBatchView.as_view(), name="api-event-batch"),
]
