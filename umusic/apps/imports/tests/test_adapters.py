import base64
import uuid
from pathlib import Path
from typing import Any

import pytest
from django.test import Client
from django.urls import reverse
from mutagen.mp3 import MP3

from umusic.apps.accounts.models import User
from umusic.apps.imports.adapter_services import _ingest_path, import_taste, import_youtube
from umusic.apps.imports.adapters import enabled_adapters, resolve_import_path
from umusic.apps.imports.models import AdapterJob, TasteCandidate
from umusic.apps.imports.remote_services import (
    _inject_youtube_id3,
    create_remote_import,
    parse_remote_urls,
    run_remote_import,
)
from umusic.apps.library.models import Artist, AudioFile, LibraryMembership, Track
from umusic.apps.library.tests.conftest import SILENT_MP3_BASE64


def test_youtube_metadata_is_embedded_in_mp3_and_filename(tmp_path: Path) -> None:
    source = tmp_path / "video.mp3"
    source.write_bytes(base64.b64decode("".join(SILENT_MP3_BASE64.split())))
    result = _inject_youtube_id3(
        source,
        {
            "id": "abc123", "track": "Training Song", "artist": "Test Singer",
            "album": "Workout Album", "release_date": "20260802",
            "genre": "Electronic", "track_number": 4,
        },
        "https://youtu.be/abc123",
    )
    assert result.name == "Test Singer - Training Song.mp3"
    tags = MP3(result).tags
    assert tags is not None
    assert str(tags["TIT2"]) == "Training Song"
    assert str(tags["TPE1"]) == "Test Singer"
    assert str(tags["TALB"]) == "Workout Album"
    assert str(tags["TDRC"]) == "2026-08-02"
    assert tags.getall("WOAS")[0].url == "https://youtu.be/abc123"


@pytest.mark.django_db
def test_flags_hide_disabled_youtube(client: Client, settings: Any) -> None:
    settings.UMUSIC_YOUTUBE_IMPORT_ENABLED = False
    user = User.objects.create_user(username="owner")
    client.force_login(user)
    assert "youtube" not in enabled_adapters()
    assert client.post(reverse("api-youtube-import"), {}).status_code == 404


def test_folder_root_blocks_traversal(settings: Any, tmp_path: Path) -> None:
    allowed = tmp_path / "allowed"
    allowed.mkdir()
    settings.UMUSIC_IMPORT_ROOTS = [allowed]
    assert resolve_import_path(str(allowed)) == allowed.resolve()
    with pytest.raises(ValueError, match="outside"):
        resolve_import_path(str(tmp_path))


@pytest.mark.django_db
def test_taste_exact_probable_and_unmatched_require_confirmation(settings: Any) -> None:
    settings.UMUSIC_TASTE_IMPORT_ENABLED = True
    owner = User.objects.create_user(username="owner")
    artist = Artist.objects.create(name="Daft Punk", normalized_name="daft punk")
    audio = AudioFile.objects.create(
        checksum="d" * 64,
        storage_backend="local",
        object_key="audio/d.mp3",
        original_filename="d.mp3",
        size_bytes=1,
        duration_ms=1000,
    )
    track = Track.objects.create(title="Around the World", artist=artist, audio_file=audio)
    LibraryMembership.objects.create(owner=owner, track=track)
    job = import_taste(
        owner,
        [
            {"artist": "Daft Punk", "title": "Around the World"},
            {"artist": "Daft Ponk", "title": "Around the Wurld"},
            {"artist": "Nobody", "title": "Unknown"},
        ],
    )
    assert list(job.candidates.values_list("state", flat=True)) == [
        "exact",
        "probable",
        "unmatched",
    ]
    assert not TasteCandidate.objects.filter(audio_acquisition_authorized=True).exists()


@pytest.mark.django_db
def test_youtube_requires_flag_and_attestation(settings: Any) -> None:
    settings.UMUSIC_YOUTUBE_IMPORT_ENABLED = True
    owner = User.objects.create_user(username="owner")
    with pytest.raises(PermissionError, match="attestation"):
        import_youtube(owner, "https://youtu.be/example", False)
    with pytest.raises(ValueError, match="YouTube"):
        import_youtube(owner, "https://example.com/audio", True)


@pytest.mark.django_db
def test_taste_adapter_api_and_confirmation_inbox(client: Client, settings: Any) -> None:
    settings.UMUSIC_TASTE_IMPORT_ENABLED = True
    settings.UMUSIC_YOUTUBE_IMPORT_ENABLED = False
    owner = User.objects.create_user(username="api-owner")
    artist = Artist.objects.create(name="Massive Attack", normalized_name="massive attack")
    audio = AudioFile.objects.create(
        checksum="e" * 64,
        storage_backend="local",
        object_key="audio/e.mp3",
        original_filename="e.mp3",
        size_bytes=1,
        duration_ms=1000,
    )
    track = Track.objects.create(title="Teardrop", artist=artist, audio_file=audio)
    LibraryMembership.objects.create(owner=owner, track=track)
    client.force_login(owner)
    assert client.get(reverse("api-adapters")).json()["enabled"]
    response = client.post(
        reverse("api-taste-import"),
        {"entries": [{"artist": "Massiv Attack", "title": "Teardrop"}]},
        content_type="application/json",
    )
    assert response.status_code == 201
    candidate = response.json()["candidates"][0]
    assert candidate["state"] == "probable"
    confirmed = client.post(
        reverse("api-taste-confirm", args=[candidate["id"]]),
        {"accept": True},
        content_type="application/json",
    )
    assert confirmed.status_code == 200
    assert confirmed.json()["state"] == "confirmed"
    assert client.get(reverse("library:adapter-inbox")).status_code == 200


@pytest.mark.django_db
def test_adapter_api_validation(client: Client, settings: Any, tmp_path: Path) -> None:
    owner = User.objects.create_user(username="validation-owner")
    client.force_login(owner)
    settings.UMUSIC_FOLDER_IMPORT_ENABLED = True
    settings.UMUSIC_TASTE_IMPORT_ENABLED = True
    settings.UMUSIC_IMPORT_ROOTS = [tmp_path / "allowed"]
    assert (
        client.post(
            reverse("api-folder-import"), {"folder": str(tmp_path)}, content_type="application/json"
        ).status_code
        == 400
    )
    assert (
        client.post(
            reverse("api-taste-import"), {"entries": []}, content_type="application/json"
        ).status_code
        == 400
    )
    assert (
        client.post(
            reverse("api-taste-confirm", args=["00000000-0000-0000-0000-000000000000"])
        ).status_code
        == 404
    )


def test_comma_and_newline_url_parser(settings: Any) -> None:
    settings.UMUSIC_REMOTE_IMPORT_MAX_ITEMS = 3
    assert parse_remote_urls("https://a.example/1.mp3, https://b.example/2.mp3\n") == [
        "https://a.example/1.mp3",
        "https://b.example/2.mp3",
    ]
    with pytest.raises(ValueError, match="Duplicate"):
        parse_remote_urls("https://a.example/1.mp3,https://a.example/1.mp3")


@pytest.mark.django_db
def test_remote_batch_is_queued_and_records_per_item_results(
    settings: Any, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings.UMUSIC_REMOTE_IMPORT_ENABLED = True
    settings.UMUSIC_YOUTUBE_IMPORT_ENABLED = True
    settings.UMUSIC_REMOTE_IMPORT_MAX_ITEMS = 5
    monkeypatch.setattr(
        "umusic.apps.imports.remote_services.socket.getaddrinfo",
        lambda *args, **kwargs: [(2, 1, 6, "", ("8.8.8.8", 443))],
    )
    monkeypatch.setattr(
        "umusic.apps.imports.tasks.process_remote_import.delay", lambda job_id: None
    )
    owner = User.objects.create_user(username="remote-owner")
    job = create_remote_import(
        owner,
        "https://music.example/song.mp3,https://youtu.be/public-video",
        attested=True,
    )
    assert job.status == "pending"
    assert list(job.remote_items.values_list("kind", flat=True)) == [
        "direct_mp3",
        "youtube",
    ]

    def fake_direct(url: str, destination: Path) -> None:
        destination.write_bytes(b"mp3")

    def fake_youtube(url: str, directory: Path) -> Path:
        path = directory / "youtube.mp3"
        path.write_bytes(b"mp3")
        return path

    monkeypatch.setattr("umusic.apps.imports.remote_services._download_direct", fake_direct)
    monkeypatch.setattr("umusic.apps.imports.remote_services._download_youtube", fake_youtube)
    monkeypatch.setattr("umusic.apps.imports.remote_services._ingest_path", lambda path, user: True)
    run_remote_import(job)
    job.refresh_from_db()
    assert job.status == "completed"
    assert job.imported_count == 2
    assert not job.remote_items.exclude(status="completed").exists()


@pytest.mark.django_db
def test_ingest_path_raises_when_inner_mp3_import_fails(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    owner = User.objects.create_user(username="failed-inner-import")
    path = tmp_path / "song.mp3"
    path.write_bytes(b"not-an-mp3")

    with pytest.raises(RuntimeError, match="INVALID_AUDIO_FORMAT"):
        _ingest_path(path, owner)


@pytest.mark.django_db
def test_remote_batch_rejects_private_targets_and_requires_youtube_attestation(
    settings: Any, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings.UMUSIC_REMOTE_IMPORT_ENABLED = True
    settings.UMUSIC_YOUTUBE_IMPORT_ENABLED = True
    owner = User.objects.create_user(username="safe-owner")
    monkeypatch.setattr(
        "umusic.apps.imports.remote_services.socket.getaddrinfo",
        lambda *args, **kwargs: [(2, 1, 6, "", ("127.0.0.1", 443))],
    )
    with pytest.raises(ValueError, match="Private"):
        create_remote_import(owner, "https://localhost/music.mp3", attested=True)
    monkeypatch.setattr(
        "umusic.apps.imports.remote_services.socket.getaddrinfo",
        lambda *args, **kwargs: [(2, 1, 6, "", ("8.8.8.8", 443))],
    )
    with pytest.raises(PermissionError, match="attestation"):
        create_remote_import(owner, "https://youtu.be/public-video", attested=False)


@pytest.mark.django_db
def test_remote_import_idempotency_creates_and_dispatches_exactly_once(
    settings: Any, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings.UMUSIC_REMOTE_IMPORT_ENABLED = True
    settings.UMUSIC_REMOTE_IMPORT_MAX_ITEMS = 5
    monkeypatch.setattr(
        "umusic.apps.imports.remote_services.socket.getaddrinfo",
        lambda *args, **kwargs: [(2, 1, 6, "", ("8.8.8.8", 443))],
    )
    dispatched: list[str] = []
    monkeypatch.setattr(
        "umusic.apps.imports.tasks.process_remote_import.delay", dispatched.append
    )
    owner = User.objects.create_user(username="idempotent-owner")
    key = uuid.uuid4()
    first = create_remote_import(
        owner, "https://music.example/song.mp3", attested=True, idempotency_key=key
    )
    second = create_remote_import(
        owner, "https://music.example/song.mp3", attested=True, idempotency_key=key
    )
    assert first.id == second.id
    assert AdapterJob.objects.filter(owner=owner, idempotency_key=key).count() == 1
    assert dispatched == [str(first.id)]
