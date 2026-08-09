from django.contrib.auth import authenticate
from django.utils import timezone
from rest_framework.permissions import AllowAny
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from umusic.apps.accounts.models import Device, User


def _device_data(device: Device) -> dict[str, object]:
    return {
        "id": str(device.id),
        "name": device.name,
        "platform": device.platform,
        "scopes": device.scopes,
        "revoked": device.revoked_at is not None,
        "created_at": device.created_at,
    }


class LoginView(APIView):
    permission_classes = [AllowAny]
    authentication_classes: list[type] = []

    def post(self, request: Request) -> Response:
        user = authenticate(
            request=request,
            username=request.data.get("username"),
            password=request.data.get("password"),
        )
        if not isinstance(user, User):
            return Response({"error": {"code": "INVALID_CREDENTIALS"}}, status=401)
        device, token = Device.issue(
            owner=user,
            name=str(request.data.get("device_name") or "iPhone"),
            platform=str(request.data.get("platform") or "ios"),
        )
        return Response({"token": token, "device": _device_data(device)}, status=201)


class MeView(APIView):
    def get(self, request: Request) -> Response:
        device = request.auth if isinstance(request.auth, Device) else None
        return Response(
            {
                "id": str(request.user.id),
                "username": request.user.username,
                "storage_quota_bytes": request.user.storage_quota_bytes,
                "device": _device_data(device) if device else None,
            }
        )


class DeviceListView(APIView):
    def get(self, request: Request) -> Response:
        return Response([_device_data(item) for item in Device.objects.filter(owner=request.user)])

    def post(self, request: Request) -> Response:
        device, token = Device.issue(
            owner=request.user,
            name=str(request.data.get("name") or "iPhone"),
            platform=str(request.data.get("platform") or "ios"),
        )
        return Response({"token": token, "device": _device_data(device)}, status=201)


class DeviceDetailView(APIView):
    def delete(self, request: Request, device_id: str) -> Response:
        device = Device.objects.filter(id=device_id, owner=request.user).first()
        if device is None:
            return Response(status=404)
        device.revoked_at = timezone.now()
        device.save(update_fields=["revoked_at"])
        return Response(status=204)


class DeviceRotateView(APIView):
    def post(self, request: Request, device_id: str) -> Response:
        old = Device.objects.filter(id=device_id, owner=request.user).first()
        if old is None:
            return Response(status=404)
        old.revoked_at = timezone.now()
        old.save(update_fields=["revoked_at"])
        device, token = Device.issue(owner=request.user, name=old.name, platform=old.platform)
        return Response({"token": token, "device": _device_data(device)}, status=201)
