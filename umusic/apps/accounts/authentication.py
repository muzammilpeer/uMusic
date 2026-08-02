from django.utils import timezone
from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed
from rest_framework.request import Request

from umusic.apps.accounts.models import Device


class DeviceTokenAuthentication(BaseAuthentication):
    keyword = "Bearer"

    def authenticate(self, request: Request):  # type: ignore[no-untyped-def]
        value = request.headers.get("Authorization", "")
        if not value.startswith(f"{self.keyword} "):
            return None
        token = value.removeprefix(f"{self.keyword} ")
        try:
            prefix, secret = token.split(".", 1)
            device = Device.objects.select_related("owner").get(
                token_prefix=prefix, revoked_at__isnull=True
            )
        except (ValueError, Device.DoesNotExist) as error:
            raise AuthenticationFailed("Invalid or revoked device token") from error
        if not device.matches(secret):
            raise AuthenticationFailed("Invalid or revoked device token")
        device.last_seen_at = timezone.now()
        device.save(update_fields=["last_seen_at"])
        request.device = device
        return device.owner, device
