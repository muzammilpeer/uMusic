import hashlib
from datetime import UTC, datetime
from itertools import pairwise

import pytest
from django.test import Client
from django.urls import reverse

from umusic.apps.accounts.models import User
from umusic.apps.contexts.models import Activity
from umusic.apps.library.models import Artist, AudioFile, LibraryMembership, Track
from umusic.apps.recommendations.generator import generate_playlist, replace_track
from umusic.apps.recommendations.models import Affinity, GeneratedPlaylist
from umusic.apps.recommendations.services import active_configuration


@pytest.fixture
def catalog(db: object) -> tuple[User, list[Track]]:
    owner = User.objects.create_user(username="generator", password="test-password")
    artists = [
        Artist.objects.create(name=f"Artist {index}", normalized_name=f"artist-{index}")
        for index in range(3)
    ]
    tracks = []
    for index in range(12):
        checksum = hashlib.sha256(str(index).encode()).hexdigest()
        audio = AudioFile.objects.create(
            checksum=checksum,
            storage_backend="local",
            object_key=f"audio/{index}.mp3",
            original_filename=f"{index}.mp3",
            size_bytes=100,
            duration_ms=180_000,
        )
        tracks.append(
            Track.objects.create(
                title=f"Track {index}",
                artist=artists[index % len(artists)],
                audio_file=audio,
                energy=None if index == 0 else f"{0.3 + (index % 6) * 0.1:.2f}",
            )
        )
    LibraryMembership.objects.bulk_create(
        [LibraryMembership(owner=owner, track=track) for track in tracks]
    )
    return owner, tracks


def generate(owner: User, seed: int = 42, activity: str = "cycling") -> GeneratedPlaylist:
    return generate_playlist(
        owner,
        activity_kind=activity,
        duration_minutes=15,
        target_energy=0.8,
        discovery=0.25,
        seed=seed,
    )


@pytest.mark.django_db
def test_equal_inputs_and_seed_reproduce_track_order(catalog: tuple[User, list[Track]]) -> None:
    owner, _ = catalog
    first = generate(owner)
    second = generate(owner)
    assert list(first.items.values_list("track_id", flat=True)) == list(
        second.items.values_list("track_id", flat=True)
    )
    assert first.input_digest == second.input_digest


@pytest.mark.django_db
def test_duration_and_explanations(catalog: tuple[User, list[Track]]) -> None:
    owner, _ = catalog
    playlist = generate(owner)
    average = 180_000
    target = 15 * 60_000
    assert abs(playlist.actual_duration_ms - target) <= average
    assert playlist.items.count() > 0
    assert all(item.reasons for item in playlist.items.all())


@pytest.mark.django_db
def test_offline_quota_selects_complete_tracks_up_to_byte_limit(
    catalog: tuple[User, list[Track]],
) -> None:
    owner, _ = catalog
    playlist = generate_playlist(
        owner,
        activity_kind="cycling",
        duration_minutes=1440,
        offline_quota_bytes=350,
        target_energy=0.8,
        discovery=0.25,
        seed=42,
    )
    assert playlist.items.count() == 3
    assert sum(
        item.track.audio_file.size_bytes
        for item in playlist.items.select_related("track__audio_file")
    ) <= 350


@pytest.mark.django_db
def test_explicit_dislike_is_hard_exclusion(catalog: tuple[User, list[Track]]) -> None:
    owner, tracks = catalog
    disliked = tracks[0]
    Affinity.objects.create(
        owner=owner,
        configuration=active_configuration(),
        target_type="track",
        target_id=str(disliked.id),
        target_label=disliked.title,
        context_type="global",
        context_key="",
        score=-1,
        confidence=1,
        explicit_preference=-1,
        last_observation=datetime(2026, 1, 1, tzinfo=UTC),
    )
    playlist = generate(owner)
    assert disliked.id not in set(playlist.items.values_list("track_id", flat=True))


@pytest.mark.django_db
def test_artist_spacing_and_missing_energy(catalog: tuple[User, list[Track]]) -> None:
    owner, _ = catalog
    playlist = generate(owner)
    items = list(playlist.items.select_related("track", "track__artist"))
    assert all(left.track.artist_id != right.track.artist_id for left, right in pairwise(items))
    assert all(item.reasons for item in items)


@pytest.mark.django_db
@pytest.mark.parametrize("activity", ["cycling", "running", "gym", "focus", "relax"])
def test_cold_start_activity_curves_generate(
    catalog: tuple[User, list[Track]], activity: str
) -> None:
    owner, _ = catalog
    playlist = generate(owner, activity=activity)
    assert playlist.items.exists()
    assert playlist.activity_kind == activity


@pytest.mark.django_db
def test_replace_creates_immutable_version(catalog: tuple[User, list[Track]]) -> None:
    owner, _ = catalog
    source = generate(owner)
    replacement = replace_track(owner, source, 0)
    assert replacement.source_version == source
    assert replacement.id != source.id
    assert replacement.items.get(position=0).track_id != source.items.get(position=0).track_id
    source.seed = 99
    with pytest.raises(RuntimeError, match="immutable"):
        source.save()


@pytest.mark.django_db
def test_generation_regeneration_replacement_and_explanation_api(
    client: Client, catalog: tuple[User, list[Track]]
) -> None:
    owner, _ = catalog
    activity = Activity.objects.create(
        name="Test Ride", slug="test-ride", kind="cycling", is_preset=True
    )
    client.force_login(owner)
    created = client.post(
        reverse("api-generate-playlist"),
        {
            "activity_id": str(activity.id),
            "duration_minutes": 5,
            "target_energy": 0.8,
            "discovery": 0.2,
            "seed": 123,
        },
        content_type="application/json",
    )
    assert created.status_code == 201
    payload = created.json()
    playlist_id = payload["id"]
    assert payload["tracks"]
    assert client.get(reverse("api-generated-playlist", args=[playlist_id])).status_code == 200
    track_id = payload["tracks"][0]["track_id"]
    explanation = client.get(reverse("api-track-explanation", args=[track_id]))
    assert explanation.status_code == 200
    assert explanation.json()["reasons"]
    regenerated = client.post(reverse("api-regenerate-playlist", args=[playlist_id]), {})
    assert regenerated.status_code == 201
    replaced = client.post(
        reverse("api-replace-generated-track", args=[playlist_id]),
        {"position": 0},
        content_type="application/json",
    )
    assert replaced.status_code == 201
    assert replaced.json()["source_version_id"] == playlist_id


@pytest.mark.django_db
def test_generation_web_workflow(client: Client, catalog: tuple[User, list[Track]]) -> None:
    owner, _ = catalog
    activity = Activity.objects.create(
        name="Web Ride", slug="web-ride", kind="cycling", is_preset=True
    )
    client.force_login(owner)
    assert client.get(reverse("library:generated-playlists")).status_code == 200
    response = client.post(
        reverse("library:generated-playlists"),
        {
            "activity_id": str(activity.id),
            "geofence_id": "",
            "duration_minutes": 5,
            "target_energy": 0.7,
            "discovery": 0.2,
            "seed": 987,
        },
    )
    assert response.status_code == 302
    detail = client.get(response["Location"])
    assert detail.status_code == 200
    assert b"Web Ride" not in detail.content
    assert b"Why" in detail.content
