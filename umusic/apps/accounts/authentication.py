from django.utils import timezone
from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed
from rest_framework.request import Request

from umusic.apps.accounts.models import Device, DeviceAccessToken


class DeviceTokenAuthentication(BaseAuthentication):
    keyword = "Bearer"

    def authenticate(self, request: Request):  # type: ignore[no-untyped-def]
        value = request.headers.get("Authorization", "")
        if not value.startswith(f"{self.keyword} "):
            return None
        token = value.removeprefix(f"{self.keyword} ")
        try:
            prefix, secret = token.split(".", 1)
            if prefix.startswith("a_"):
                access = DeviceAccessToken.objects.select_related("device__owner").get(
                    token_prefix=prefix,
                    revoked_at__isnull=True,
                    expires_at__gt=timezone.now(),
                    device__revoked_at__isnull=True,
                    device__owner__is_active=True,
                )
                if not access.matches(secret):
                    raise AuthenticationFailed("Invalid or revoked device token")
                device = access.device
                device.last_seen_at = timezone.now()
                device.save(update_fields=["last_seen_at"])
                request.device = device
                return device.owner, device
            device = Device.objects.select_related("owner").get(
                token_prefix=prefix, revoked_at__isnull=True, owner__is_active=True
            )
        except (ValueError, Device.DoesNotExist, DeviceAccessToken.DoesNotExist) as error:
            raise AuthenticationFailed("Invalid or revoked device token") from error
        if not device.matches(secret):
            raise AuthenticationFailed("Invalid or revoked device token")
        device.last_seen_at = timezone.now()
        device.save(update_fields=["last_seen_at"])
        request.device = device
        return device.owner, device
