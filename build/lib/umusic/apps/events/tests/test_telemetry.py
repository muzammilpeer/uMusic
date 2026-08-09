import uuid
from datetime import UTC, datetime, timedelta

import pytest
from django.test import Client
from django.urls import reverse

from umusic.apps.accounts.models import User
from umusic.apps.events.models import ListeningEvent, PlayFact
from umusic.apps.events.services import MAX_LISTENED_DELTA_MS, rebuild_play_facts
from umusic.apps.library.models import Artist, AudioFile, LibraryMembership, Track


@pytest.fixture
def owner_and_track(db: object) -> tuple[User, Track]:
    owner = User.objects.create_user(username="owner", password="test-password")
    artist = Artist.objects.create(name="Telemetry", normalized_name="telemetry")
    audio = AudioFile.objects.create(
        checksum="b" * 64,
        storage_backend="local",
        object_key="audio/telemetry.mp3",
        original_filename="telemetry.mp3",
        size_bytes=100,
        duration_ms=100_000,
    )
    track = Track.objects.create(title="Signals", artist=artist, audio_file=audio)
    LibraryMembership.objects.create(owner=owner, track=track)
    return owner, track


def payload(
    track: Track, playback_id: uuid.UUID, event_type: str, **overrides: object
) -> dict[str, object]:
    result: dict[str, object] = {
        "client_event_id": str(uuid.uuid4()),
        "playback_id": str(playback_id),
        "track_id": str(track.id),
        "event_type": event_type,
        "client_timestamp": datetime.now(UTC).isoformat(),
        "position_ms": 0,
        "duration_ms": 100_000,
    }
    result.update(overrides)
    return result


@pytest.mark.django_db
def test_retried_batch_is_idempotent(client: Client, owner_and_track: tuple[User, Track]) -> None:
    owner, track = owner_and_track
    client.force_login(owner)
    event = payload(track, uuid.uuid4(), "started")
    first = client.post(
        reverse("api-event-batch"), {"events": [event]}, content_type="application/json"
    )
    retry = client.post(
        reverse("api-event-batch"), {"events": [event]}, content_type="application/json"
    )
    assert first.status_code == retry.status_code == 202
    assert first.json()["accepted"] == 1
    assert retry.json()["duplicates"] == 1
    assert ListeningEvent.objects.count() == 1


@pytest.mark.django_db
def test_reordered_offline_events_rebuild_by_client_time(
    owner_and_track: tuple[User, Track],
) -> None:
    owner, track = owner_and_track
    playback_id = uuid.uuid4()
    now = datetime.now(UTC)
    ListeningEvent.objects.create(
        owner=owner,
        track=track,
        playback_id=playback_id,
        client_event_id=uuid.uuid4(),
        event_type="skipped",
        client_timestamp=now,
        position_ms=10_000,
        duration_ms=100_000,
        offline=True,
    )
    ListeningEvent.objects.create(
        owner=owner,
        track=track,
        playback_id=playback_id,
        client_event_id=uuid.uuid4(),
        event_type="started",
        client_timestamp=now - timedelta(minutes=5),
        duration_ms=100_000,
        offline=True,
    )
    assert rebuild_play_facts(owner) == 1
    fact = PlayFact.objects.get(playback_id=playback_id)
    assert fact.early_skip is True
    assert fact.first_event_at == now - timedelta(minutes=5)


@pytest.mark.django_db
def test_completion_replay_feedback_and_heartbeat_rules(
    owner_and_track: tuple[User, Track],
) -> None:
    owner, track = owner_and_track
    playback_id = uuid.uuid4()
    now = datetime.now(UTC)
    for index, (kind, position, delta) in enumerate(
        [
            ("started", 0, 0),
            ("progress", 95_000, 99_000),
            ("seeked", 99_000, 0),
            ("replayed", 0, 0),
            ("liked", 1_000, 0),
        ]
    ):
        ListeningEvent.objects.create(
            owner=owner,
            track=track,
            playback_id=playback_id,
            client_event_id=uuid.uuid4(),
            event_type=kind,
            client_timestamp=now + timedelta(seconds=index),
            position_ms=position,
            duration_ms=100_000,
            listened_ms_delta=delta,
        )
    rebuild_play_facts(owner)
    fact = PlayFact.objects.get(playback_id=playback_id)
    assert fact.completed is True
    assert fact.replayed is True
    assert fact.explicit_feedback == 1
    assert fact.listening_ms == MAX_LISTENED_DELTA_MS


@pytest.mark.django_db
def test_clock_skew_and_short_track_completion_are_accepted(
    client: Client, owner_and_track: tuple[User, Track]
) -> None:
    owner, track = owner_and_track
    client.force_login(owner)
    future = datetime.now(UTC) + timedelta(days=2)
    event = payload(
        track,
        uuid.uuid4(),
        "completed",
        client_timestamp=future.isoformat(),
        position_ms=900,
        duration_ms=1000,
    )
    response = client.post(
        reverse("api-event-batch"), {"events": [event]}, content_type="application/json"
    )
    assert response.status_code == 202
    assert PlayFact.objects.get().completed is True


@pytest.mark.django_db
def test_raw_events_are_append_only(owner_and_track: tuple[User, Track]) -> None:
    owner, track = owner_and_track
    event = ListeningEvent.objects.create(
        owner=owner,
        track=track,
        playback_id=uuid.uuid4(),
        client_event_id=uuid.uuid4(),
        event_type="started",
        client_timestamp=datetime.now(UTC),
    )
    event.position_ms = 10
    with pytest.raises(RuntimeError, match="append-only"):
        event.save()
    with pytest.raises(RuntimeError, match="retained"):
        event.delete()
