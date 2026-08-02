from django.urls import path

from umusic.apps.accounts.api import (
    DeviceDetailView,
    DeviceListView,
    DeviceRotateView,
    LoginView,
    MeView,
)

urlpatterns = [
    path("auth/login", LoginView.as_view(), name="api-login"),
    path("me", MeView.as_view(), name="api-me"),
    path("devices", DeviceListView.as_view(), name="device-list"),
    path("devices/<uuid:device_id>", DeviceDetailView.as_view(), name="device-detail"),
    path(
        "devices/<uuid:device_id>/rotate-token",
        DeviceRotateView.as_view(),
        name="device-rotate",
    ),
]
