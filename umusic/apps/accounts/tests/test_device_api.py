import pytest
from django.test import Client
from rest_framework.test import APIClient

from umusic.apps.accounts.models import Device, User


@pytest.mark.django_db
def test_device_login_authentication_and_revocation() -> None:
    user = User.objects.create_user(username="mobile", password="good-password")
    client = APIClient()
    response = client.post(
        "/api/v1/auth/login",
        {"username": "mobile", "password": "good-password", "device_name": "Road iPhone"},
        format="json",
    )
    assert response.status_code == 201
    token = response.data["token"]
    device_id = response.data["device"]["id"]

    bearer = APIClient()
    bearer.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
    assert bearer.get("/api/v1/me").data["username"] == "mobile"

    device = Device.objects.get(id=device_id)
    device.scopes = []
    device.save(update_fields=["scopes"])
    assert bearer.get("/api/v1/me").status_code == 403
    device.scopes = ["library:read"]
    device.save(update_fields=["scopes"])

    client.force_authenticate(user=user)
    assert client.delete(f"/api/v1/devices/{device_id}").status_code == 204
    assert bearer.get("/api/v1/me").status_code == 403
    assert Device.objects.get(id=device_id).revoked_at is not None


@pytest.mark.django_db
def test_invalid_login_and_token_rotation() -> None:
    user = User.objects.create_user(username="owner", password="good-password")
    client = APIClient()
    assert (
        client.post(
            "/api/v1/auth/login",
            {"username": "owner", "password": "wrong"},
            format="json",
        ).status_code
        == 401
    )
    client.force_authenticate(user=user)
    created = client.post("/api/v1/devices", {"name": "Phone"}, format="json")
    rotated = client.post(
        f"/api/v1/devices/{created.data['device']['id']}/rotate-token", {}, format="json"
    )
    assert rotated.status_code == 201
    assert rotated.data["token"] != created.data["token"]


@pytest.mark.django_db
def test_owner_can_revoke_device_from_web_portal() -> None:
    user = User.objects.create_user(username="web-owner")
    device, _ = Device.issue(owner=user, name="iPad")
    client = Client()
    client.force_login(user)
    assert client.get("/library/devices/").status_code == 200
    assert client.post("/library/devices/", {"device_id": str(device.id)}).status_code == 302
    device.refresh_from_db()
    assert device.revoked_at is not None
