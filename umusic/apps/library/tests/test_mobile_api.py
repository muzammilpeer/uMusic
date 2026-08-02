import pytest
from rest_framework.test import APIClient

from umusic.apps.accounts.models import User
from umusic.apps.library.models import Album, Artist, AudioFile, Track


@pytest.mark.django_db
def test_paginated_mobile_catalog_and_search() -> None:
    owner = User.objects.create_user(username="mobile-catalog")
    artist = Artist.objects.create(name="Air", normalized_name="air-mobile")
    album = Album.objects.create(
        title="Moon Safari", normalized_title="moon safari", album_artist=artist
    )
    audio = AudioFile.objects.create(
        checksum="9" * 64,
        storage_backend="local",
        object_key="audio/9.mp3",
        original_filename="kelly.mp3",
        size_bytes=10,
        duration_ms=240_000,
    )
    track = Track.objects.create(
        title="Kelly Watch the Stars", artist=artist, album=album, audio_file=audio
    )
    client = APIClient()
    client.force_authenticate(owner)
    response = client.get("/api/v1/tracks?q=Kelly")
    assert response.status_code == 200
    assert response.data["count"] == 1
    assert response.data["results"][0]["stream_path"].endswith(f"{track.id}/stream/")
    assert client.get(f"/api/v1/tracks/{track.id}").status_code == 200
    assert client.get("/api/v1/artists").data[0]["name"] == "Air"
    assert client.get("/api/v1/albums").data[0]["title"] == "Moon Safari"
