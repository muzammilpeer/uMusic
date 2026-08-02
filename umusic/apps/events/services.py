from collections import defaultdict
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import datetime
from typing import Any
from uuid import UUID

from django.db import transaction

from umusic.apps.accounts.models import User
from umusic.apps.events.models import ListeningEvent, PlayFact

HEARTBEAT_INTERVAL_SECONDS = 15
MAX_LISTENED_DELTA_MS = HEARTBEAT_INTERVAL_SECONDS * 2 * 1000
COMPLETION_RATIO = 0.90
EARLY_SKIP_RATIO = 0.20


@dataclass
class FactAccumulator:
    owner_id: int
    track_id: UUID
    playback_id: UUID
    first_event_at: datetime
    last_event_at: datetime
    listening_ms: int = 0
    furthest_position_ms: int = 0
    duration_ms: int = 0
    completed: bool = False
    skipped: bool = False
    replayed: bool = False
    explicit_feedback: int = 0
    event_count: int = 0

    def add(self, event: ListeningEvent) -> None:
        self.first_event_at = min(self.first_event_at, event.client_timestamp)
        self.last_event_at = max(self.last_event_at, event.client_timestamp)
        self.listening_ms += min(event.listened_ms_delta, MAX_LISTENED_DELTA_MS)
        self.furthest_position_ms = max(self.furthest_position_ms, event.position_ms)
        self.duration_ms = max(self.duration_ms, event.duration_ms)
        self.completed |= event.event_type == ListeningEvent.Type.COMPLETED
        self.skipped |= event.event_type == ListeningEvent.Type.SKIPPED
        self.replayed |= event.event_type == ListeningEvent.Type.REPLAYED
        if event.event_type == ListeningEvent.Type.LIKED:
            self.explicit_feedback = 1
        elif event.event_type == ListeningEvent.Type.DISLIKED:
            self.explicit_feedback = -1
        self.event_count += 1


def rebuild_play_facts(owner: User | None = None) -> int:
    events = ListeningEvent.objects.select_related("track").order_by(
        "owner_id", "playback_id", "client_timestamp", "received_at"
    )
    if owner is not None:
        events = events.filter(owner=owner)
    accumulators: dict[tuple[int, UUID], FactAccumulator] = {}
    for event in events.iterator():
        key = (event.owner_id, event.playback_id)
        fact = accumulators.get(key)
        if fact is None:
            fact = FactAccumulator(
                owner_id=event.owner_id,
                track_id=event.track_id,
                playback_id=event.playback_id,
                first_event_at=event.client_timestamp,
                last_event_at=event.client_timestamp,
            )
            accumulators[key] = fact
        fact.add(event)

    owner_ids = {item.owner_id for item in accumulators.values()}
    if owner is not None:
        owner_ids.add(owner.id)
    with transaction.atomic():
        # Event batches can arrive concurrently from the Mac, iPhone, and restored
        # offline queue. Serialize each owner's delete/rebuild cycle so two requests
        # cannot both bulk-insert the same unique playback fact.
        if owner is not None:
            User.objects.select_for_update().get(pk=owner.pk)
        elif owner_ids:
            list(User.objects.select_for_update().filter(id__in=owner_ids).order_by("id"))
        PlayFact.objects.filter(owner_id__in=owner_ids).delete()
        PlayFact.objects.bulk_create(
            [
                PlayFact(
                    owner_id=item.owner_id,
                    track_id=item.track_id,
                    playback_id=item.playback_id,
                    first_event_at=item.first_event_at,
                    last_event_at=item.last_event_at,
                    listening_ms=min(item.listening_ms, item.duration_ms or item.listening_ms),
                    furthest_position_ms=item.furthest_position_ms,
                    duration_ms=item.duration_ms,
                    completed=item.completed
                    or bool(
                        item.duration_ms
                        and item.furthest_position_ms / item.duration_ms >= COMPLETION_RATIO
                    ),
                    skipped=item.skipped,
                    early_skip=bool(
                        item.skipped
                        and item.duration_ms
                        and item.furthest_position_ms / item.duration_ms <= EARLY_SKIP_RATIO
                    ),
                    replayed=item.replayed,
                    explicit_feedback=item.explicit_feedback,
                    event_count=item.event_count,
                )
                for item in accumulators.values()
            ]
        )
    return len(accumulators)


def group_events_by_playback(events: Iterable[ListeningEvent]) -> dict[UUID, list[ListeningEvent]]:
    grouped: dict[UUID, list[ListeningEvent]] = defaultdict(list)
    for event in events:
        grouped[event.playback_id].append(event)
    return grouped


def event_defaults(payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "playback_id": payload["playback_id"],
        "track_id": payload["track_id"],
        "playback_session_id": payload.get("playback_session_id"),
        "context_snapshot_id": payload.get("context_snapshot_id"),
        "event_type": payload["event_type"],
        "client_timestamp": payload["client_timestamp"],
        "position_ms": max(0, int(payload.get("position_ms", 0))),
        "duration_ms": max(0, int(payload.get("duration_ms", 0))),
        "listened_ms_delta": min(
            MAX_LISTENED_DELTA_MS, max(0, int(payload.get("listened_ms_delta", 0)))
        ),
        "offline": bool(payload.get("offline", False)),
        "metadata": payload.get("metadata", {}),
    }
