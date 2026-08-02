import pytest
from django.test import Client
from django.urls import reverse

from umusic.apps.accounts.models import User
from umusic.apps.library.models import Artist, AudioFile, Track


@pytest.mark.django_db
def test_create_empty_playback_session(client: Client) -> None:
    user = User.objects.create_user(username="owner", password="test-password")
    client.force_login(user)
    response = client.post(
        reverse("api-playback-sessions"), data={"track_ids": []}, content_type="application/json"
    )
    assert response.status_code == 201
    assert response.json()["queue"] == []


@pytest.mark.django_db
def test_update_queue_and_resume_session(client: Client) -> None:
    user = User.objects.create_user(username="owner", password="test-password")
    artist = Artist.objects.create(name="Rider", normalized_name="rider")
    audio = AudioFile.objects.create(
        checksum="a" * 64,
        storage_backend="local",
        object_key="audio/test.mp3",
        original_filename="test.mp3",
        size_bytes=10,
        duration_ms=1000,
    )
    track = Track.objects.create(title="Road", artist=artist, audio_file=audio)
    client.force_login(user)
    created = client.post(
        reverse("api-playback-sessions"),
        data={"track_ids": [str(track.id).upper()]},
        content_type="application/json",
    ).json()
    detail_url = reverse("api-playback-session", args=[created["id"]])
    updated = client.patch(
        detail_url,
        data={"position_ms": 4200, "current_track_id": str(track.id)},
        content_type="application/json",
    )
    assert updated.status_code == 200
    assert updated.json()["position_ms"] == 4200
    queue = client.patch(
        reverse("api-playback-queue", args=[created["id"]]),
        data={"track_ids": []},
        content_type="application/json",
    )
    assert queue.status_code == 200
    assert client.get(detail_url).json()["queue"] == []


@pytest.mark.django_db
def test_continuation_validates_input_and_missing_source(client: Client) -> None:
    user = User.objects.create_user(username="rider", password="test-password")
    client.force_login(user)
    session = client.post(
        reverse("api-playback-sessions"),
        data={"track_ids": []},
        content_type="application/json",
    ).json()
    url = reverse("api-playback-continuation", args=[session["id"]])
    malformed = client.post(
        url,
        data={"played_track_ids": "not-a-list", "desired_count": "bad"},
        content_type="application/json",
    )
    assert malformed.status_code == 400
    missing_source = client.post(url, data={}, content_type="application/json")
    assert missing_source.status_code == 409
