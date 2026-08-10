from django.urls import path

from umusic.apps.accounts.v2_api import (
    BootstrapV2View,
    LogoutSessionV2View,
    RefreshSessionV2View,
    SessionV2View,
)

urlpatterns = [
    path("bootstrap", BootstrapV2View.as_view(), name="api-v2-bootstrap"),
    path("auth/session", SessionV2View.as_view(), name="api-v2-session"),
    path("auth/session/refresh", RefreshSessionV2View.as_view(), name="api-v2-session-refresh"),
    path("auth/session/logout", LogoutSessionV2View.as_view(), name="api-v2-session-logout"),
]
