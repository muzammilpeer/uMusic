import pytest
from django.test import Client
from django.urls import reverse

from umusic.apps.accounts.models import User


@pytest.mark.django_db
def test_playlist_is_private_to_owner(client: Client) -> None:
    owner = User.objects.create_user(username="owner", password="test-password")
    other = User.objects.create_user(username="other", password="test-password")
    client.force_login(owner)
    created = client.post(
        reverse("api-playlists"), data={"name": "Cycling"}, content_type="application/json"
    )
    assert created.status_code == 201
    playlist_id = created.json()["id"]
    client.force_login(other)
    assert client.get(reverse("api-playlist", args=[playlist_id])).status_code == 404


@pytest.mark.django_db
def test_playlist_edit_list_and_delete(client: Client) -> None:
    owner = User.objects.create_user(username="owner", password="test-password")
    client.force_login(owner)
    created = client.post(
        reverse("api-playlists"), data={"name": "Cycling"}, content_type="application/json"
    )
    url = reverse("api-playlist", args=[created.json()["id"]])
    edited = client.patch(
        url,
        data={"name": "Fast Cycling", "description": "Road music", "track_ids": []},
        content_type="application/json",
    )
    assert edited.status_code == 200
    assert edited.json()["name"] == "Fast Cycling"
    assert len(client.get(reverse("api-playlists")).json()) == 1
    assert client.delete(url).status_code == 204
    assert client.get(url).status_code == 404
