import hashlib
from collections.abc import Iterator
from pathlib import Path
from typing import cast

import pytest
from django.http import StreamingHttpResponse
from rest_framework.test import APIClient

from umusic.apps.accounts.models import Device, User
from umusic.apps.contexts.models import Activity
from umusic.apps.library.models import Artist, AudioFile, Track
from umusic.apps.library.storage import audio_object_key
from umusic.apps.recommendations.models import GeneratedPlaylist, GeneratedPlaylistTrack


@pytest.mark.django_db
def test_manifest_acknowledgement_and_download(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr("django.conf.settings.MEDIA_ROOT", tmp_path)
    owner = User.objects.create_user(username="sync-owner")
    device, _ = Device.issue(owner=owner, name="iPhone")
    content = b"ID3-test-mp3"
    checksum = hashlib.sha256(content).hexdigest()
    key = audio_object_key(checksum)
    path = tmp_path / key
    path.parent.mkdir(parents=True)
    path.write_bytes(content)
    artist = Artist.objects.create(name="Artist", normalized_name="artist-sync")
    audio = AudioFile.objects.create(
        checksum=checksum,
        storage_backend="local",
        object_key=key,
        original_filename="song.mp3",
        size_bytes=len(content),
        duration_ms=120_000,
    )
    track = Track.objects.create(title="Song", artist=artist, audio_file=audio)
    playlist = GeneratedPlaylist.objects.create(
        owner=owner,
        activity_kind="cycling",
        requested_duration_minutes=30,
        actual_duration_ms=120_000,
        target_energy="0.80",
        discovery="0.20",
        seed=7,
        model_version="rules-v3",
        input_digest="a" * 64,
    )
    GeneratedPlaylistTrack.objects.create(
        playlist=playlist,
        track=track,
        position=1,
        score="0.90",
        target_energy="0.80",
    )
    client = APIClient()
    client.force_authenticate(user=owner)
    created = client.post(
        f"/api/v1/devices/{device.id}/sync-plans",
        {"playlist_id": str(playlist.id)},
        format="json",
    )
    assert created.status_code == 201
    plan_id = created.data["id"]
    manifest = client.get(f"/api/v1/sync-plans/{plan_id}/manifest")
    assert manifest.status_code == 200
    entry = manifest.data["entries"][0]
    assert entry["sha256"] == checksum
    download = client.get(entry["download_url"])
    assert b"".join(download.streaming_content) == content
    resumed = client.get(entry["download_url"], HTTP_RANGE="bytes=4-")
    assert resumed.status_code == 206
    assert b"".join(resumed.streaming_content) == content[4:]

    acknowledged = client.post(
        f"/api/v1/sync-plans/{plan_id}/acknowledge",
        {"downloaded_track_ids": [str(track.id)]},
        format="json",
    )
    assert acknowledged.status_code == 200
    assert acknowledged.data["acknowledged_at"] is not None

    device.revoked_at = playlist.created_at
    device.save(update_fields=["revoked_at"])
    assert client.get(entry["download_url"]).status_code == 401


@pytest.mark.django_db
def test_server_to_prepared_airplane_mode_workout_journey(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    media_root = tmp_path / "server-media"
    device_cache = tmp_path / "iphone-offline"
    device_cache.mkdir()
    monkeypatch.setattr("django.conf.settings.MEDIA_ROOT", media_root)
    owner = User.objects.create_user(username="field-rider")
    device, _ = Device.issue(owner=owner, name="Field iPhone")
    activity = Activity.objects.create(
        name="Field Cycling", slug="field-cycling", kind="cycling",
        phase_curve=["warmup", "sustain", "cooldown"], is_preset=True,
    )
    artist = Artist.objects.create(name="Road Test", normalized_name="road-test")
    expected: dict[str, bytes] = {}
    for index in range(3):
        content = b"ID3" + bytes([index]) * 64
        checksum = hashlib.sha256(content).hexdigest()
        key = audio_object_key(checksum)
        path = media_root / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        audio = AudioFile.objects.create(
            checksum=checksum, storage_backend="local", object_key=key,
            original_filename=f"ride-{index}.mp3", size_bytes=len(content), duration_ms=120_000,
        )
        track = Track.objects.create(
            title=f"Ride {index}", artist=artist, audio_file=audio,
            energy=0.5 + index * 0.2,
        )
        expected[str(track.id)] = content

    client = APIClient()
    client.force_authenticate(user=owner)
    generated = client.post(
        "/api/v1/recommendations/session-playlist/",
        {
            "activity_id": str(activity.id), "duration_minutes": 6,
            "target_energy": 0.8, "discovery": 0.2, "seed": 13,
        },
        format="json",
    )
    assert generated.status_code == 201
    plan = client.post(
        f"/api/v1/devices/{device.id}/sync-plans",
        {"playlist_id": generated.data["id"]}, format="json",
    )
    manifest = client.get(f"/api/v1/sync-plans/{plan.data['id']}/manifest")
    assert manifest.status_code == 200
    assert len(manifest.data["entries"]) == 3

    downloaded_ids = []
    for entry in manifest.data["entries"]:
        response = cast(StreamingHttpResponse, client.get(entry["download_url"]))
        content = b"".join(cast(Iterator[bytes], response.streaming_content))
        assert hashlib.sha256(content).hexdigest() == entry["sha256"]
        (device_cache / f"{entry['track_id']}.mp3").write_bytes(content)
        downloaded_ids.append(entry["track_id"])
    acknowledged = client.post(
        f"/api/v1/sync-plans/{plan.data['id']}/acknowledge",
        {"downloaded_track_ids": downloaded_ids, "failed_track_ids": []}, format="json",
    )
    assert acknowledged.status_code == 200

    # Airplane-mode boundary: no server/API calls occur below this line.
    for track_id in downloaded_ids:
        assert (device_cache / f"{track_id}.mp3").read_bytes() == expected[track_id]
