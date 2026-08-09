from django.urls import path

from umusic.apps.operations.views import live, metrics, ready

urlpatterns = [
    path("live/", live, name="health-live"),
    path("ready/", ready, name="health-ready"),
    path("metrics/", metrics, name="health-metrics"),
]
