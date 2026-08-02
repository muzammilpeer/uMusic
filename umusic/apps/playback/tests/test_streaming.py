import hashlib
from collections.abc import Iterator
from pathlib import Path
from typing import Any, cast

import pytest
from django.http import StreamingHttpResponse
from django.test import Client
from django.urls import reverse

from umusic.apps.accounts.models import User
from umusic.apps.library.models import Artist, AudioFile, Track
from umusic.apps.library.storage import audio_object_key, get_media_storage


@pytest.fixture
def stream_track(db: Any, settings: Any, tmp_path: Path) -> tuple[Track, bytes]:
    settings.MEDIA_ROOT = tmp_path / "media"
    content = b"ID3" + bytes(range(100))
    source = tmp_path / "track.mp3"
    source.write_bytes(content)
    checksum = hashlib.sha256(content).hexdigest()
    storage = get_media_storage()
    key = audio_object_key(checksum)
    storage.publish(source, key, checksum)
    artist = Artist.objects.create(name="Rider", normalized_name="rider")
    audio = AudioFile.objects.create(
        checksum=checksum,
        storage_backend=storage.backend_id,
        object_key=key,
        original_filename="track.mp3",
        size_bytes=len(content),
        duration_ms=1000,
    )
    return Track.objects.create(title="Road", artist=artist, audio_file=audio), content


@pytest.mark.django_db
def test_stream_requires_authentication(client: Client, stream_track: tuple[Track, bytes]) -> None:
    track, _ = stream_track
    assert client.get(reverse("api-track-stream", args=[track.id])).status_code == 401


@pytest.mark.django_db
def test_full_and_range_stream(client: Client, stream_track: tuple[Track, bytes]) -> None:
    track, content = stream_track
    user = User.objects.create_user(username="owner", password="test-password")
    client.force_login(user)
    full = client.get(reverse("api-track-stream", args=[track.id]))
    assert full.status_code == 200
    full_content = cast(Iterator[bytes], cast(StreamingHttpResponse, full).streaming_content)
    assert b"".join(full_content) == content
    partial = client.get(reverse("api-track-stream", args=[track.id]), HTTP_RANGE="bytes=3-9")
    assert partial.status_code == 206
    assert partial["Content-Range"] == f"bytes 3-9/{len(content)}"
    partial_content = cast(Iterator[bytes], cast(StreamingHttpResponse, partial).streaming_content)
    assert b"".join(partial_content) == content[3:10]


@pytest.mark.django_db
def test_invalid_range_returns_416(client: Client, stream_track: tuple[Track, bytes]) -> None:
    track, content = stream_track
    user = User.objects.create_user(username="owner", password="test-password")
    client.force_login(user)
    response = client.get(reverse("api-track-stream", args=[track.id]), HTTP_RANGE="bytes=999-1000")
    assert response.status_code == 416
    assert response["Content-Range"] == f"bytes */{len(content)}"
