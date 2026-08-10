import uuid
from typing import Any

from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APIClient, APITestCase

from umusic.apps.accounts.models import Device, DeviceAccessToken, DeviceRefreshToken, User


class V2AuthenticationAPITests(APITestCase):
    def login(
        self, client: APIClient, username: str = "owner", password: str = "good-password"
    ) -> Any:
        return client.post(
            "/api/v2/auth/session",
            {
                "username": username,
                "password": password,
                "device": {
                    "installation_id": "00000000-0000-0000-0000-000000000123",
                    "platform": "ios",
                    "app_version": "2.0.0-alpha.2",
                },
            },
            format="json",
            HTTP_X_REQUEST_ID="test-request",
        )

    def test_bootstrap_is_public_and_non_personal(self) -> None:
        response = APIClient().get("/api/v2/bootstrap")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["api_version"], "v2")
        self.assertTrue({"catalog_sync", "audio_stream"}.issubset(response.data["capabilities"]))
        self.assertNotIn("user", response.data)

    def test_login_access_refresh_logout_flow(self) -> None:
        User.objects.create_user(username="owner", password="good-password", first_name="Owner")
        client = APIClient()
        login = self.login(client)
        self.assertEqual(login.status_code, 201)
        self.assertEqual(login.data["user"]["display_name"], "Owner")
        self.assertIsInstance(uuid.UUID(login.data["user"]["id"]), uuid.UUID)
        self.assertTrue(login.data["access_token"].startswith("a_"))
        self.assertTrue(login.data["refresh_token"].startswith("r_"))
        self.assertEqual(DeviceAccessToken.objects.exclude(token_hash="").count(), 1)
        self.assertNotIn(login.data["access_token"], str(DeviceAccessToken.objects.values()))

        bearer = APIClient()
        bearer.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access_token']}")
        self.assertEqual(bearer.get("/api/v1/me").status_code, 200)

        refresh = client.post(
            "/api/v2/auth/session/refresh",
            {"refresh_token": login.data["refresh_token"]},
            format="json",
        )
        self.assertEqual(refresh.status_code, 200)
        self.assertNotEqual(refresh.data["access_token"], login.data["access_token"])
        self.assertNotEqual(refresh.data["refresh_token"], login.data["refresh_token"])

        renewed = APIClient()
        renewed.credentials(HTTP_AUTHORIZATION=f"Bearer {refresh.data['access_token']}")
        self.assertEqual(renewed.post("/api/v2/auth/session/logout").status_code, 204)
        self.assertEqual(renewed.get("/api/v1/me").status_code, 403)

    def test_refresh_reuse_revokes_entire_device(self) -> None:
        User.objects.create_user(username="owner", password="good-password")
        client = APIClient()
        login = self.login(client)
        rotated = client.post(
            "/api/v2/auth/session/refresh",
            {"refresh_token": login.data["refresh_token"]},
            format="json",
        )
        replay = client.post(
            "/api/v2/auth/session/refresh",
            {"refresh_token": login.data["refresh_token"]},
            format="json",
        )
        self.assertEqual(replay.status_code, 403)
        self.assertEqual(replay.data["code"], "refresh_reuse")
        device = Device.objects.get()
        device.refresh_from_db()
        self.assertIsNotNone(device.revoked_at)

        bearer = APIClient()
        bearer.credentials(HTTP_AUTHORIZATION=f"Bearer {rotated.data['access_token']}")
        self.assertEqual(bearer.get("/api/v1/me").status_code, 403)

    def test_rejects_invalid_credentials_device_and_inactive_user(self) -> None:
        user = User.objects.create_user(username="owner", password="good-password")
        client = APIClient()
        self.assertEqual(self.login(client, password="wrong").status_code, 401)
        malformed = client.post(
            "/api/v2/auth/session",
            {"username": "owner", "password": "good-password", "device": {}},
            format="json",
        )
        self.assertEqual(malformed.status_code, 400)
        user.is_active = False
        user.save(update_fields=["is_active"])
        self.assertEqual(self.login(client).status_code, 401)

    @override_settings(UMUSIC_V2_REFRESH_TOKEN_TTL_SECONDS=-1)
    def test_expired_refresh_is_rejected(self) -> None:
        User.objects.create_user(username="owner", password="good-password")
        client = APIClient()
        login = self.login(client)
        refresh = DeviceRefreshToken.objects.get()
        self.assertLess(refresh.expires_at, timezone.now())
        response = client.post(
            "/api/v2/auth/session/refresh",
            {"refresh_token": login.data["refresh_token"]},
            format="json",
        )
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.data["code"], "refresh_expired")

    def test_errors_are_redacted_and_include_request_id(self) -> None:
        User.objects.create_user(username="owner", password="good-password")
        response = self.login(APIClient(), password="do-not-echo")
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.data["request_id"], "test-request")
        self.assertNotIn("do-not-echo", str(response.data))
