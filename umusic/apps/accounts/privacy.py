from typing import Any

from umusic.apps.accounts.models import Device, User
from umusic.apps.contexts.models import ContextSnapshot, Geofence
from umusic.apps.events.models import ListeningEvent, PlayFact
from umusic.apps.playlists.models import Playlist
from umusic.apps.recommendations.models import Affinity, GeneratedPlaylist, LearningRun


def _rows(queryset: Any, *fields: str) -> list[dict[str, Any]]:
    return list(queryset.values(*fields))


def export_owner_data(owner: User) -> dict[str, object]:
    return {
        "schema_version": 1,
        "profile": {"username": owner.username, "email": owner.email},
        "devices": _rows(
            Device.objects.filter(owner=owner),
            "id", "name", "platform", "scopes", "last_seen_at", "revoked_at", "created_at",
        ),
        "places": _rows(
            Geofence.objects.filter(owner=owner),
            "id", "name", "latitude", "longitude", "radius_m", "privacy", "created_at",
        ),
        "contexts": _rows(
            ContextSnapshot.objects.filter(owner=owner),
            "id", "activity_name", "activity_kind", "phase", "geofence_reference",
            "geofence_name", "planned_duration_minutes", "target_energy", "created_at",
        ),
        "listening_events": _rows(
            ListeningEvent.objects.filter(owner=owner),
            "client_event_id", "playback_id", "track_id", "context_snapshot_id",
            "event_type", "client_timestamp", "position_ms", "duration_ms", "offline",
        ),
        "play_facts": _rows(
            PlayFact.objects.filter(owner=owner),
            "playback_id", "track_id", "listening_ms", "completed", "early_skip",
            "explicit_feedback",
        ),
        "affinities": _rows(
            Affinity.objects.filter(owner=owner),
            "target_type", "target_id", "target_label", "context_type", "context_key",
            "score", "confidence", "explicit_preference",
        ),
        "generated_playlists": _rows(
            GeneratedPlaylist.objects.filter(owner=owner),
            "id", "source_version_id", "activity_kind", "model_version", "seed", "created_at",
        ),
        "playlists": _rows(Playlist.objects.filter(owner=owner), "id", "name", "description"),
    }


def delete_listening_and_learning(owner: User) -> dict[str, int]:
    events, _ = ListeningEvent.objects.filter(owner=owner).delete()
    facts, _ = PlayFact.objects.filter(owner=owner).delete()
    affinities, _ = Affinity.objects.filter(owner=owner).delete()
    runs, _ = LearningRun.objects.filter(owner=owner).delete()
    return {"events": events, "facts": facts, "affinities": affinities, "learning_runs": runs}
