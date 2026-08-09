import uuid

import pytest
from django.test import Client
from django.urls import reverse

from umusic.apps.accounts.models import User
from umusic.apps.contexts.models import Activity, ContextForgetRecord, ContextSnapshot, Geofence
from umusic.apps.events.models import ListeningEvent
from umusic.apps.library.models import Artist, AudioFile, AuditEvent, LibraryMembership, Track


@pytest.fixture
def owners(db: object) -> tuple[User, User]:
    return (
        User.objects.create_user(username="owner", password="test-password"),
        User.objects.create_user(username="other", password="test-password"),
    )


@pytest.fixture
def cycling(db: object) -> Activity:
    return Activity.objects.create(
        name="Cycling", slug=f"cycling-{uuid.uuid4()}", kind="cycling", is_preset=True
    )


@pytest.mark.django_db
def test_manual_snapshot_contains_place_reference_without_coordinates(
    client: Client, owners: tuple[User, User], cycling: Activity
) -> None:
    owner, _ = owners
    place = Geofence.objects.create(
        owner=owner, name="Park", latitude="25.123456", longitude="55.123456", radius_m=200
    )
    client.force_login(owner)
    response = client.post(
        reverse("api-context-snapshots"),
        data={
            "activity_id": str(cycling.id),
            "geofence_id": str(place.id),
            "planned_duration_minutes": 45,
            "target_energy": "0.80",
            "discovery": "0.25",
        },
        content_type="application/json",
    )
    assert response.status_code == 201
    data = response.json()
    assert data["geofence_reference"] == str(place.id)
    assert "latitude" not in data and "longitude" not in data


@pytest.mark.django_db
def test_context_snapshot_is_immutable(owners: tuple[User, User], cycling: Activity) -> None:
    owner, _ = owners
    snapshot = ContextSnapshot.objects.create(
        owner=owner,
        activity=cycling,
        activity_name="Cycling",
        activity_kind="cycling",
        time_bucket="morning",
    )
    snapshot.target_energy = "0.90"
    with pytest.raises(RuntimeError, match="immutable"):
        snapshot.save()


@pytest.mark.django_db
def test_place_access_is_owner_scoped(client: Client, owners: tuple[User, User]) -> None:
    owner, other = owners
    place = Geofence.objects.create(
        owner=owner, name="Home", latitude="25.000000", longitude="55.000000", radius_m=100
    )
    client.force_login(other)
    assert client.get(reverse("api-geofence", args=[place.id])).status_code == 404
    assert client.delete(reverse("api-geofence", args=[place.id])).status_code == 404


@pytest.mark.django_db
def test_deleting_place_removes_coordinates_but_preserves_snapshot_and_audit(
    client: Client, owners: tuple[User, User], cycling: Activity
) -> None:
    owner, _ = owners
    place = Geofence.objects.create(
        owner=owner, name="Track", latitude="25.000000", longitude="55.000000", radius_m=100
    )
    snapshot = ContextSnapshot.objects.create(
        owner=owner,
        activity=cycling,
        activity_name="Cycling",
        activity_kind="cycling",
        geofence_reference=place.id,
        geofence_name=place.name,
        time_bucket="evening",
    )
    client.force_login(owner)
    assert client.delete(reverse("api-geofence", args=[place.id])).status_code == 204
    assert not Geofence.objects.filter(id=place.id).exists()
    snapshot.refresh_from_db()
    assert snapshot.geofence_reference == place.id
    assert ContextForgetRecord.objects.filter(geofence_reference=place.id).exists()
    assert AuditEvent.objects.filter(
        action="context.place_deleted", target_id=str(place.id)
    ).exists()


@pytest.mark.django_db
def test_forget_learning_keeps_place(client: Client, owners: tuple[User, User]) -> None:
    owner, _ = owners
    place = Geofence.objects.create(
        owner=owner, name="Office", latitude="25.000000", longitude="55.000000", radius_m=100
    )
    client.force_login(owner)
    response = client.post(reverse("api-geofence-forget", args=[place.id]))
    assert response.status_code == 201
    assert Geofence.objects.filter(id=place.id).exists()
    assert ContextForgetRecord.objects.filter(owner=owner, geofence_reference=place.id).exists()


@pytest.mark.django_db
def test_session_and_event_carry_owned_snapshot(
    client: Client, owners: tuple[User, User], cycling: Activity
) -> None:
    owner, _ = owners
    snapshot = ContextSnapshot.objects.create(
        owner=owner,
        activity=cycling,
        activity_name="Cycling",
        activity_kind="cycling",
        time_bucket="morning",
    )
    artist = Artist.objects.create(name="Context", normalized_name="context")
    audio = AudioFile.objects.create(
        checksum="c" * 64,
        storage_backend="local",
        object_key="audio/context.mp3",
        original_filename="context.mp3",
        size_bytes=100,
        duration_ms=1000,
    )
    track = Track.objects.create(title="Ride", artist=artist, audio_file=audio)
    LibraryMembership.objects.create(owner=owner, track=track)
    client.force_login(owner)
    session_response = client.post(
        reverse("api-playback-sessions"),
        {"track_ids": [str(track.id)], "context_snapshot_id": str(snapshot.id)},
        content_type="application/json",
    )
    assert session_response.status_code == 201
    event_response = client.post(
        reverse("api-event-batch"),
        {
            "events": [
                {
                    "client_event_id": str(uuid.uuid4()),
                    "playback_id": str(uuid.uuid4()),
                    "track_id": str(track.id),
                    "context_snapshot_id": str(snapshot.id),
                    "event_type": "started",
                    "client_timestamp": "2026-08-02T12:00:00Z",
                }
            ]
        },
        content_type="application/json",
    )
    assert event_response.status_code == 202
    assert ListeningEvent.objects.get().context_snapshot == snapshot
