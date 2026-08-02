from collections.abc import Iterator
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest
from django.conf import settings
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client, override_settings
from mutagen.mp3 import MP3

from umusic.apps.accounts.models import User
from umusic.apps.library.models import AudioFile, ImportJob, Track
from umusic.apps.library.storage import LocalFilesystemStorage, StorageError, get_media_storage

pytestmark = pytest.mark.django_db


@pytest.fixture
def owner() -> User:
    return User.objects.create_user(username="owner", password="a-secure-test-password")


@pytest.fixture
def authenticated_client(owner: User) -> Client:
    client = Client()
    client.force_login(owner)
    return client


@pytest.fixture
def media_settings(tmp_path: Path) -> Iterator[None]:
    with override_settings(
        MEDIA_ROOT=tmp_path / "media",
        UMUSIC_QUARANTINE_ROOT=tmp_path / "quarantine",
        UMUSIC_STORAGE_BACKEND="local",
        UMUSIC_MAX_UPLOAD_BYTES=1024 * 1024,
    ):
        yield


def upload(client: Client, content: bytes, name: str = "test.mp3") -> Any:
    return client.post(
        "/api/v1/imports/uploads/",
        {"file": SimpleUploadedFile(name, content, content_type="audio/mpeg")},
    )


def upload_many(client: Client, files: list[SimpleUploadedFile]) -> Any:
    return client.post("/api/v1/imports/uploads/", {"files": files})


def test_valid_mp3_is_imported_with_metadata(
    authenticated_client: Client, mp3_bytes: bytes, media_settings: None
) -> None:
    response = upload(authenticated_client, mp3_bytes)

    assert response.status_code == 201
    assert response.json()["status"] == "completed"
    track = Track.objects.select_related("artist", "album", "audio_file").get()
    assert track.title == "Test Tone"
    assert track.artist.name == "uMusic Tests"
    assert track.album is not None and track.album.title == "Test Album"
    assert track.audio_file.duration_ms > 0
    assert Path(track.audio_file.object_key).is_absolute() is False


def test_duplicate_upload_reuses_audio_and_track(
    authenticated_client: Client, mp3_bytes: bytes, media_settings: None
) -> None:
    first = upload(authenticated_client, mp3_bytes)
    second = upload(authenticated_client, mp3_bytes, "copy.mp3")

    assert first.status_code == second.status_code == 201
    assert second.json()["status"] == "duplicate"
    assert Track.objects.count() == 1
    assert AudioFile.objects.count() == 1
    assert ImportJob.objects.filter(status=ImportJob.Status.DUPLICATE).count() == 1


def test_non_mp3_extension_is_rejected_before_quarantine(
    authenticated_client: Client, mp3_bytes: bytes, media_settings: None
) -> None:
    response = upload(authenticated_client, mp3_bytes, "renamed.wav")

    assert response.status_code == 400
    assert response.json()["error"]["code"] == "INVALID_EXTENSION"
    assert ImportJob.objects.count() == 0


def test_corrupt_mp3_is_rejected_and_quarantine_is_cleaned(
    authenticated_client: Client, media_settings: None, tmp_path: Path
) -> None:
    response = upload(authenticated_client, b"not an mp3")

    assert response.status_code == 400
    assert response.json()["error_code"] == "INVALID_AUDIO_FORMAT"
    assert Track.objects.count() == 0
    assert list((tmp_path / "quarantine").glob("*")) == []


@override_settings(UMUSIC_MAX_UPLOAD_BYTES=4)
def test_oversized_upload_is_rejected(authenticated_client: Client, media_settings: None) -> None:
    response = upload(authenticated_client, b"more than four bytes")

    assert response.status_code == 400
    assert response.json()["error_code"] == "FILE_TOO_LARGE"
    assert Track.objects.count() == 0


def test_storage_failure_does_not_create_library_rows(
    authenticated_client: Client, mp3_bytes: bytes, media_settings: None, tmp_path: Path
) -> None:
    storage = LocalFilesystemStorage(tmp_path / "media")
    with patch.object(storage, "publish", side_effect=StorageError("unavailable")):
        with patch("umusic.apps.library.services.get_media_storage", return_value=storage):
            response = upload(authenticated_client, mp3_bytes)

    assert response.status_code == 400
    assert response.json()["error_code"] == "STORAGE_ERROR"
    assert Track.objects.count() == 0
    assert AudioFile.objects.count() == 0


def test_upload_api_requires_authentication(mp3_bytes: bytes, media_settings: None) -> None:
    response = upload(Client(), mp3_bytes)

    assert response.status_code in {401, 403}


def test_import_job_api_is_owner_scoped(owner: User) -> None:
    other = User.objects.create_user(username="other")
    job = ImportJob.objects.create(owner=owner, source_filename="owner.mp3")
    client = Client()
    client.force_login(other)

    response = client.get(f"/api/v1/imports/{job.id}/")

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "NOT_FOUND"


def test_multiple_mp3_files_are_processed_in_one_request(
    authenticated_client: Client, mp3_bytes: bytes, media_settings: None
) -> None:
    response = upload_many(
        authenticated_client,
        [
            SimpleUploadedFile("first.mp3", mp3_bytes, content_type="audio/mpeg"),
            SimpleUploadedFile("second.mp3", mp3_bytes, content_type="audio/mpeg"),
        ],
    )

    assert response.status_code == 201
    assert response.json()["summary"] == {"total": 2, "successful": 2, "failed": 0}
    assert [job["status"] for job in response.json()["jobs"]] == ["completed", "duplicate"]
    assert Track.objects.count() == 1


@override_settings(UMUSIC_MAX_UPLOAD_FILES=1)
def test_multiple_upload_respects_batch_limit(
    authenticated_client: Client, mp3_bytes: bytes, media_settings: None
) -> None:
    response = upload_many(
        authenticated_client,
        [
            SimpleUploadedFile("first.mp3", mp3_bytes),
            SimpleUploadedFile("second.mp3", mp3_bytes),
        ],
    )

    assert response.status_code == 400
    assert response.json()["error"]["code"] == "TOO_MANY_FILES"
    assert ImportJob.objects.count() == 0


def test_portal_metadata_update_rewrites_id3_checksum_and_filename(
    authenticated_client: Client, owner: User, mp3_bytes: bytes, media_settings: None
) -> None:
    assert upload(authenticated_client, mp3_bytes).status_code == 201
    track = Track.objects.select_related("audio_file").get()
    old_key = track.audio_file.object_key
    old_checksum = track.audio_file.checksum
    response = authenticated_client.post(
        f"/library/tracks/{track.id}/",
        {
            "title": "Fast Ride", "artist": "Cycling Singer", "album": "Road Album",
            "year": 2026, "track_number": 2, "disc_number": 1,
            "genres": "Workout, Electronic",
        },
    )
    assert response.status_code == 302
    track.refresh_from_db()
    track.audio_file.refresh_from_db()
    assert track.title == "Fast Ride"
    assert track.artist.name == "Cycling Singer"
    assert track.album is not None and track.album.title == "Road Album"
    assert track.audio_file.original_filename == "Cycling Singer - Fast Ride.mp3"
    assert track.audio_file.checksum != old_checksum
    storage = get_media_storage()
    assert not storage.exists(old_key)
    assert storage.verify(track.audio_file.object_key, track.audio_file.checksum)
    with storage.open(track.audio_file.object_key) as source:
        rewritten = Path(settings.UMUSIC_QUARANTINE_ROOT) / "inspect-rewritten.mp3"
        rewritten.parent.mkdir(parents=True, exist_ok=True)
        rewritten.write_bytes(source.read())
    tags = MP3(rewritten).tags
    assert tags is not None
    assert str(tags["TIT2"]) == "Fast Ride"
    assert str(tags["TPE1"]) == "Cycling Singer"
    assert str(tags["TALB"]) == "Road Album"
