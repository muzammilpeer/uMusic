from typing import Any

from rest_framework.permissions import BasePermission
from rest_framework.request import Request

from umusic.apps.accounts.models import Device


class DeviceScopePermission(BasePermission):
    """Apply narrow scopes to device tokens; browser sessions retain owner access."""

    def has_permission(self, request: Request, view: Any) -> bool:
        if not isinstance(request.auth, Device):
            return True
        required = "library:read"
        if "/events/" in request.path:
            required = "events:write"
        elif "/sync-" in request.path or "/sync-plans" in request.path:
            required = "sync:read"
        elif "/playback/" in request.path and request.method != "GET":
            required = "playback:write"
        return required in request.auth.scopes
