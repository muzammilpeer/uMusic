import uuid
from datetime import timedelta

from django.conf import settings
from django.contrib.auth import authenticate
from django.db import transaction
from django.utils import timezone
from rest_framework.permissions import AllowAny
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from umusic.apps.accounts.models import (
    Device,
    DeviceAccessToken,
    DeviceRefreshToken,
    User,
)

CAPABILITIES = ["catalog_sync", "audio_stream", "remote_import"]


def _request_id(request: Request) -> str:
    return str(getattr(request._request, "request_id", request.headers.get("X-Request-ID", "")))


def _error(
    request: Request, *, code: str, message: str, status: int, retryable: bool = False
) -> Response:
    return Response(
        {
            "code": code,
            "message": message,
            "field_errors": {},
            "retryable": retryable,
            "request_id": _request_id(request),
        },
        status=status,
    )


def _issue_session(device: Device) -> dict[str, object]:
    now = timezone.now()
    _, access = DeviceAccessToken.issue(
        device=device,
        expires_at=now + timedelta(seconds=settings.UMUSIC_V2_ACCESS_TOKEN_TTL_SECONDS),
    )
    _, refresh = DeviceRefreshToken.issue(
        device=device,
        expires_at=now + timedelta(seconds=settings.UMUSIC_V2_REFRESH_TOKEN_TTL_SECONDS),
    )
    return {
        "access_token": access,
        "expires_at": now + timedelta(seconds=settings.UMUSIC_V2_ACCESS_TOKEN_TTL_SECONDS),
        "refresh_token": refresh,
        "user": {
            "id": str(device.owner.public_id),
            "display_name": device.owner.get_full_name() or device.owner.username,
        },
        "capabilities": CAPABILITIES,
    }


def _parse_token(value: object) -> tuple[str, str] | None:
    try:
        prefix, secret = str(value).split(".", 1)
    except ValueError:
        return None
    return (prefix, secret) if prefix and secret else None


class BootstrapV2View(APIView):
    permission_classes = [AllowAny]
    authentication_classes: list[type] = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "bootstrap_v2"

    def get(self, request: Request) -> Response:
        return Response(
            {
                "server_id": "umusic-private-server",
                "api_version": "v2",
                "schema_version": 1,
                "capabilities": CAPABILITIES,
                "library_count": 0,
            }
        )


class SessionV2View(APIView):
    permission_classes = [AllowAny]
    authentication_classes: list[type] = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth_v2"

    def post(self, request: Request) -> Response:
        username = str(request.data.get("username") or "")
        password = str(request.data.get("password") or "")
        device_data = (
            request.data.get("device") if isinstance(request.data.get("device"), dict) else {}
        )
        user = authenticate(request=request, username=username, password=password)
        if not isinstance(user, User) or not user.is_active:
            return _error(
                request,
                code="invalid_credentials",
                message="The username or password was not accepted.",
                status=401,
            )
        try:
            installation_id = uuid.UUID(str(device_data.get("installation_id")))
        except (TypeError, ValueError, AttributeError):
            return _error(
                request,
                code="invalid_device",
                message="A valid installation identifier is required.",
                status=400,
            )
        platform = str(device_data.get("platform") or "ios")[:30]
        device, _legacy_token = Device.issue(
            owner=user,
            name=f"uMusic {platform} {str(installation_id)[:8]}",
            platform=platform,
        )
        return Response(_issue_session(device), status=201)


class RefreshSessionV2View(APIView):
    permission_classes = [AllowAny]
    authentication_classes: list[type] = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth_v2"

    @transaction.atomic
    def post(self, request: Request) -> Response:
        parsed = _parse_token(request.data.get("refresh_token"))
        if parsed is None:
            return _error(
                request,
                code="invalid_refresh",
                message="The session cannot be refreshed.",
                status=401,
            )
        prefix, secret = parsed
        refresh = (
            DeviceRefreshToken.objects.select_for_update()
            .select_related("device__owner")
            .filter(token_prefix=prefix)
            .first()
        )
        if refresh is None or not refresh.matches(secret):
            return _error(
                request,
                code="invalid_refresh",
                message="The session cannot be refreshed.",
                status=401,
            )
        device = refresh.device
        now = timezone.now()
        if refresh.used_at is not None:
            device.revoked_at = now
            device.save(update_fields=["revoked_at"])
            DeviceAccessToken.objects.filter(device=device, revoked_at__isnull=True).update(
                revoked_at=now
            )
            DeviceRefreshToken.objects.filter(device=device, revoked_at__isnull=True).update(
                revoked_at=now
            )
            return _error(
                request, code="refresh_reuse", message="The device session was revoked.", status=403
            )
        if (
            refresh.revoked_at is not None
            or device.revoked_at is not None
            or not device.owner.is_active
        ):
            return _error(
                request,
                code="session_revoked",
                message="The device session was revoked.",
                status=403,
            )
        if refresh.expires_at <= now:
            refresh.revoked_at = now
            refresh.save(update_fields=["revoked_at"])
            return _error(
                request, code="refresh_expired", message="The session has expired.", status=401
            )

        refresh.used_at = now
        refresh.save(update_fields=["used_at"])
        payload = _issue_session(device)
        replacement_prefix, _secret = str(payload["refresh_token"]).split(".", 1)
        refresh.replaced_by = DeviceRefreshToken.objects.get(token_prefix=replacement_prefix)
        refresh.save(update_fields=["replaced_by"])
        return Response(payload)


class LogoutSessionV2View(APIView):
    def post(self, request: Request) -> Response:
        device = request.auth if isinstance(request.auth, Device) else None
        if device is None:
            return _error(
                request, code="invalid_session", message="The session is invalid.", status=401
            )
        now = timezone.now()
        device.revoked_at = now
        device.save(update_fields=["revoked_at"])
        DeviceAccessToken.objects.filter(device=device, revoked_at__isnull=True).update(
            revoked_at=now
        )
        DeviceRefreshToken.objects.filter(device=device, revoked_at__isnull=True).update(
            revoked_at=now
        )
        return Response(status=204)
