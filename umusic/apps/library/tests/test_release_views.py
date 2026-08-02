import json
import uuid
from datetime import UTC, datetime

import pytest
from django.test import Client
from django.urls import reverse

from umusic.apps.accounts.models import Device, User
from umusic.apps.events.models import ListeningEvent
from umusic.apps.library.models import Artist, AudioFile, Track
from umusic.apps.recommendations.models import GeneratedPlaylist, GeneratedPlaylistTrack


@pytest.fixture
def release_owner(db: object) -> User:
    return User.objects.create_user(
        username="release-owner", email="release@example.com", password="test-password"
    )


@pytest.mark.django_db
def test_export_excludes_credentials_and_history_can_be_deleted(
    client: Client, release_owner: User
) -> None:
    device, _ = Device.issue(owner=release_owner, name="Private iPhone")
    artist = Artist.objects.create(name="Release", normalized_name="release")
    audio = AudioFile.objects.create(
        checksum="f" * 64, storage_backend="local", object_key="audio/release.mp3",
        original_filename="release.mp3", size_bytes=10, duration_ms=1_000,
    )
    track = Track.objects.create(title="Final", artist=artist, audio_file=audio)
    ListeningEvent.objects.create(
        owner=release_owner, client_event_id=uuid.uuid4(), playback_id=uuid.uuid4(),
        track=track, event_type="started", client_timestamp=datetime.now(UTC),
    )
    assert client.login(username=release_owner.username, password="test-password")
    response = client.get(reverse("library:privacy-export"))
    assert response.status_code == 200
    payload = json.loads(response.content)
    assert payload["devices"][0]["id"] == str(device.id)
    assert "token_hash" not in response.content.decode()
    assert "password" not in response.content.decode()

    wrong = client.post(
        reverse("library:privacy"),
        {"action": "delete_history", "confirmation": "delete"},
    )
    assert wrong.status_code == 200
    assert ListeningEvent.objects.filter(owner=release_owner).exists()
    accepted = client.post(
        reverse("library:privacy"),
        {"action": "delete_history", "confirmation": "DELETE HISTORY"},
    )
    assert accepted.status_code == 302
    assert not ListeningEvent.objects.filter(owner=release_owner).exists()


@pytest.mark.django_db
def test_evaluation_dashboard_and_account_deletion(client: Client, release_owner: User) -> None:
    playlist = GeneratedPlaylist.objects.create(
        owner=release_owner, activity_kind="cycling", requested_duration_minutes=30,
        target_energy="0.80", discovery="0.20", seed=1, model_version="generator-v1",
        input_digest="a" * 64,
    )
    artist = Artist.objects.create(name="Metric", normalized_name="metric")
    audio = AudioFile.objects.create(
        checksum="e" * 64, storage_backend="local", object_key="audio/metric.mp3",
        original_filename="metric.mp3", size_bytes=10, duration_ms=1_000,
    )
    track = Track.objects.create(title="Measured", artist=artist, audio_file=audio)
    GeneratedPlaylistTrack.objects.create(
        playlist=playlist, track=track, position=0, score="0.9", target_energy="0.8",
        reasons=[{"code": "COLD_START"}],
    )
    assert client.login(username=release_owner.username, password="test-password")
    response = client.get(reverse("library:evaluation"))
    assert response.status_code == 200
    assert response.context["rows"][0]["explained_rate"] == 1.0

    deleted = client.post(
        reverse("library:privacy"),
        {"action": "delete_account", "confirmation": "DELETE ACCOUNT"},
    )
    assert deleted.status_code == 302
    assert not User.objects.filter(id=release_owner.id).exists()
