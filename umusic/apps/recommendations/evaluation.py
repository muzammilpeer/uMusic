from dataclasses import asdict, dataclass

from umusic.apps.accounts.models import User
from umusic.apps.events.models import ListeningEvent, PlayFact
from umusic.apps.recommendations.models import GeneratedPlaylist


@dataclass(frozen=True)
class EvaluationRow:
    playlist_id: str
    activity: str
    model_version: str
    created_at: str
    plays: int
    completion_rate: float
    early_skip_rate: float
    approval_rate: float
    artist_diversity: int
    catalog_coverage: int
    explained_rate: float
    exploration_acceptance_rate: float


def evaluation_rows(owner: User, limit: int = 200) -> list[dict[str, object]]:
    playlists = GeneratedPlaylist.objects.filter(owner=owner).select_related(
        "context_snapshot"
    )[:limit]
    rows = []
    for playlist in playlists:
        items = list(playlist.items.select_related("track__artist"))
        playback_ids = ListeningEvent.objects.filter(
            owner=owner,
            context_snapshot_id=playlist.context_snapshot_id,
            track_id__in=[item.track_id for item in items],
        ).values_list("playback_id", flat=True)
        facts = list(PlayFact.objects.filter(owner=owner, playback_id__in=playback_ids))
        plays = len(facts)
        completed = sum(item.completed for item in facts)
        approved = sum(item.explicit_feedback > 0 for item in facts)
        rows.append(
            asdict(
                EvaluationRow(
                    playlist_id=str(playlist.id),
                    activity=playlist.activity_kind,
                    model_version=playlist.model_version,
                    created_at=playlist.created_at.isoformat(),
                    plays=plays,
                    completion_rate=round(completed / plays, 3) if plays else 0,
                    early_skip_rate=(
                        round(sum(item.early_skip for item in facts) / plays, 3) if plays else 0
                    ),
                    approval_rate=round(approved / plays, 3) if plays else 0,
                    artist_diversity=len({item.track.artist_id for item in items}),
                    catalog_coverage=len({item.track_id for item in items}),
                    explained_rate=(
                        round(sum(bool(item.reasons) for item in items) / len(items), 3)
                        if items
                        else 0
                    ),
                    exploration_acceptance_rate=(
                        round(completed / plays, 3) if plays and playlist.discovery > 0 else 0
                    ),
                )
            )
        )
    return rows
