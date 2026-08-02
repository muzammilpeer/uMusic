import uuid
from datetime import UTC, datetime, timedelta

import pytest

from umusic.apps.accounts.models import User
from umusic.apps.contexts.models import ContextForgetRecord, ContextSnapshot
from umusic.apps.events.models import ListeningEvent, PlayFact
from umusic.apps.library.models import Artist, AudioFile, Track
from umusic.apps.recommendations.models import Affinity
from umusic.apps.recommendations.services import rebuild_affinities


@pytest.fixture
def owner(db: object) -> User:
    return User.objects.create_user(username="learner", password="test-password")


def make_track(owner: User, suffix: str, genres: list[str] | None = None) -> Track:
    artist, _ = Artist.objects.get_or_create(
        normalized_name=f"artist-{suffix}", defaults={"name": f"Artist {suffix}"}
    )
    audio = AudioFile.objects.create(
        checksum=(suffix * 64)[:64],
        storage_backend="local",
        object_key=f"audio/{suffix}.mp3",
        original_filename=f"{suffix}.mp3",
        size_bytes=100,
        duration_ms=100_000,
    )
    return Track.objects.create(
        title=f"Track {suffix}", artist=artist, audio_file=audio, genres=genres or []
    )


def make_fact(
    owner: User,
    track: Track,
    observed: datetime,
    *,
    completed: bool = False,
    skipped: bool = False,
    early_skip: bool = False,
    replayed: bool = False,
    feedback: int = 0,
) -> PlayFact:
    return PlayFact.objects.create(
        owner=owner,
        track=track,
        playback_id=uuid.uuid4(),
        first_event_at=observed,
        last_event_at=observed,
        duration_ms=100_000,
        completed=completed,
        skipped=skipped,
        early_skip=early_skip,
        replayed=replayed,
        explicit_feedback=feedback,
        event_count=2,
    )


@pytest.mark.django_db
def test_rebuild_is_deterministic(owner: User) -> None:
    track = make_track(owner, "a", ["Electronic"])
    make_fact(owner, track, datetime(2026, 1, 1, tzinfo=UTC), completed=True)
    first = rebuild_affinities(owner)
    first_rows = list(
        Affinity.objects.filter(owner=owner).values_list(
            "target_type", "target_id", "context_type", "context_key", "score", "confidence"
        )
    )
    second = rebuild_affinities(owner)
    second_rows = list(
        Affinity.objects.filter(owner=owner).values_list(
            "target_type", "target_id", "context_type", "context_key", "score", "confidence"
        )
    )
    assert first.evidence_digest == second.evidence_digest
    assert first_rows == second_rows


@pytest.mark.django_db
def test_explicit_dislike_overrides_positive_history(owner: User) -> None:
    track = make_track(owner, "b")
    base = datetime(2026, 1, 1, tzinfo=UTC)
    for day in range(5):
        make_fact(owner, track, base + timedelta(days=day), completed=True)
    make_fact(owner, track, base + timedelta(days=6), feedback=-1)
    rebuild_affinities(owner)
    affinity = Affinity.objects.get(
        owner=owner, target_type="track", target_id=str(track.id), context_type="global"
    )
    assert affinity.score == -1
    assert affinity.confidence == 1
    assert affinity.explicit_preference == -1


@pytest.mark.django_db
def test_one_ambiguous_skip_has_low_confidence(owner: User) -> None:
    track = make_track(owner, "c")
    make_fact(owner, track, datetime(2026, 1, 1, tzinfo=UTC), skipped=True)
    rebuild_affinities(owner)
    affinity = Affinity.objects.get(
        owner=owner, target_type="track", target_id=str(track.id), context_type="global"
    )
    assert abs(affinity.score) < 0.1
    assert affinity.confidence <= 0.5


@pytest.mark.django_db
def test_implicit_signal_decays_and_missing_genres_are_safe(owner: User) -> None:
    old_track = make_track(owner, "d")
    new_track = make_track(owner, "e")
    make_fact(owner, old_track, datetime(2025, 1, 1, tzinfo=UTC), completed=True)
    make_fact(owner, new_track, datetime(2026, 1, 1, tzinfo=UTC), completed=True)
    rebuild_affinities(owner)
    old_score = Affinity.objects.get(target_type="track", target_id=str(old_track.id)).score
    new_score = Affinity.objects.get(target_type="track", target_id=str(new_track.id)).score
    assert old_score < new_score
    assert not Affinity.objects.filter(target_type="genre").exists()


@pytest.mark.django_db
def test_context_is_isolated_and_forgotten_place_is_excluded(owner: User) -> None:
    track = make_track(owner, "f")
    observed = datetime(2026, 1, 1, tzinfo=UTC)
    fact = make_fact(owner, track, observed, completed=True)
    place_id = uuid.uuid4()
    snapshot = ContextSnapshot.objects.create(
        owner=owner,
        activity_name="Cycling",
        activity_kind="cycling",
        geofence_reference=place_id,
        geofence_name="Park",
        time_bucket="morning",
    )
    ListeningEvent.objects.create(
        owner=owner,
        track=track,
        context_snapshot=snapshot,
        playback_id=fact.playback_id,
        client_event_id=uuid.uuid4(),
        event_type="completed",
        client_timestamp=observed,
        duration_ms=100_000,
        position_ms=100_000,
    )
    ContextForgetRecord.objects.create(owner=owner, geofence_reference=place_id)
    rebuild_affinities(owner)
    assert Affinity.objects.filter(context_type="activity", context_key="cycling").exists()
    assert not Affinity.objects.filter(context_type="activity", context_key="running").exists()
    assert not Affinity.objects.filter(context_type="place", context_key=str(place_id)).exists()
