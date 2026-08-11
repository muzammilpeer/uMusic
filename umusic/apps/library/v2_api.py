import base64
from datetime import UTC, datetime

from django.core import signing
from django.db.models import Q
from django.db.models.functions import Greatest
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from umusic.apps.library.models import LibraryMembership

CURSOR_SALT = "umusic-v2-library-cursor"
MAX_LIMIT = 500
CONTENT_CATEGORIES = {"quran", "quranTranslation", "religious"}


def _content_classifications(value: object) -> list[dict[str, object]]:
    if not isinstance(value, list):
        return []
    result = []
    for item in value:
        if not isinstance(item, dict) or item.get("category") not in CONTENT_CATEGORIES:
            continue
        try:
            confidence = float(item.get("confidence", 0))
        except (TypeError, ValueError):
            continue
        result.append({"category": item["category"], "confidence": min(max(confidence, 0), 1)})
    return result


def _encode_cursor(
    *, since: datetime, until: datetime | None, active_offset: int, tomb_offset: int
) -> str:
    return signing.dumps(
        {
            "since": since.isoformat(),
            "until": until.isoformat() if until else None,
            "active_offset": active_offset,
            "tomb_offset": tomb_offset,
        },
        salt=CURSOR_SALT,
        compress=True,
    )


def _decode_cursor(value: str | None) -> tuple[datetime, datetime, int, int]:
    epoch = datetime(1970, 1, 1, tzinfo=UTC)
    if not value:
        return epoch, timezone.now(), 0, 0
    payload = signing.loads(value, salt=CURSOR_SALT, max_age=365 * 24 * 60 * 60)
    since = parse_datetime(str(payload["since"]))
    raw_until = payload["until"]
    until = timezone.now() if raw_until is None else parse_datetime(str(raw_until))
    if since is None or until is None:
        raise signing.BadSignature("Invalid cursor dates")
    return since, until, max(int(payload["active_offset"]), 0), max(int(payload["tomb_offset"]), 0)


def _track_payload(membership: LibraryMembership) -> dict[str, object]:
    track = membership.track
    audio = track.audio_file
    album = track.album
    artwork = track.artwork
    revision_time = max(track.updated_at, membership.updated_at)
    analysis = getattr(track, "analysis", None)
    song_features = None
    if analysis is not None and analysis.status == "succeeded" and analysis.source_checksum == audio.checksum.lower():
        song_features = {
            "schema_version": analysis.feature_schema_version,
            "provider": analysis.provider,
            "model_version": analysis.model_version,
            "analysis_revision": int(analysis.updated_at.timestamp() * 1_000_000),
            "scalars": analysis.scalar_features,
            "embedding": {
                "encoding": analysis.embedding_encoding,
                "dimension": analysis.embedding_dimension,
                "payload": base64.b64encode(bytes(analysis.embedding)).decode("ascii"),
            },
        }
    return {
        "id": str(track.id),
        "revision": int(revision_time.timestamp() * 1_000_000),
        "title": track.title,
        "artists": [{"id": str(track.artist_id), "name": track.artist.name}],
        "album": (
            {
                "id": str(album.id),
                "title": album.title,
                "album_artist": album.album_artist.name if album.album_artist else None,
            }
            if album
            else None
        ),
        "genres": track.genres,
        "language": None,
        "release_date": None,
        "release_year": track.year,
        "duration_ms": audio.duration_ms,
        "track_number": track.track_number,
        "disc_number": track.disc_number,
        "explicit": False,
        "content_tags": [],
        "content_classifications": _content_classifications(track.content_classifications),
        "audio_analysis": {
            "version": "metadata-1",
            "bpm": None,
            "energy": float(track.energy) if track.energy is not None else None,
            "valence": None,
            "danceability": None,
            "instrumental_probability": None,
            "speech_probability": None,
        },
        "song_features": song_features,
        "artwork": ({"id": artwork.checksum, "etag": artwork.checksum} if artwork else None),
        "audio": {
            "id": audio.checksum,
            "bytes": audio.size_bytes,
            "mime_type": "audio/mpeg",
            "bitrate_kbps": round(audio.bitrate / 1000) if audio.bitrate else None,
        },
        "available": track.is_active,
    }


class LibraryChangesV2View(APIView):
    def get(self, request: Request) -> Response:
        try:
            limit = min(max(int(request.query_params.get("limit", 500)), 1), MAX_LIMIT)
            since, until, active_offset, tomb_offset = _decode_cursor(
                request.query_params.get("cursor")
            )
        except (TypeError, ValueError, KeyError, signing.BadSignature):
            return Response(
                {
                    "code": "invalid_cursor",
                    "message": "The library cursor is invalid or expired.",
                    "field_errors": {"cursor": ["Invalid cursor"]},
                    "retryable": False,
                    "request_id": str(getattr(request._request, "request_id", "")),
                },
                status=400,
            )

        active = (
            LibraryMembership.objects.filter(
                owner=request.user,
                state=LibraryMembership.State.ACTIVE,
                track__is_active=True,
            )
            .annotate(change_time=Greatest("updated_at", "track__updated_at"))
            .filter(change_time__gt=since, change_time__lte=until)
            .select_related(
                "track__artist",
                "track__album__album_artist",
                "track__artwork",
                "track__audio_file",
                "track__analysis",
            )
            .order_by("change_time", "id")
        )
        active_page = list(active[active_offset : active_offset + limit])
        remaining = limit - len(active_page)
        tombstones = LibraryMembership.objects.filter(
            Q(removed_at__gt=since),
            removed_at__lte=until,
            owner=request.user,
            state=LibraryMembership.State.REMOVED,
        ).order_by("removed_at", "id")
        tomb_page = list(tombstones[tomb_offset : tomb_offset + remaining]) if remaining else []
        next_active = active_offset + len(active_page)
        next_tomb = tomb_offset + len(tomb_page)
        has_more = next_active < active.count() or next_tomb < tombstones.count()
        next_cursor = _encode_cursor(
            since=since if has_more else until,
            until=until if has_more else None,
            active_offset=next_active if has_more else 0,
            tomb_offset=next_tomb if has_more else 0,
        )
        return Response(
            {
                "schema_version": 1,
                "library_revision": str(int(until.timestamp() * 1_000_000)),
                "next_cursor": next_cursor,
                "has_more": has_more,
                "tracks": [_track_payload(item) for item in active_page],
                "tombstones": [
                    {
                        "track_id": str(item.track_id),
                        "revision": int(item.removed_at.timestamp() * 1_000_000),
                        "deleted_at": item.removed_at,
                    }
                    for item in tomb_page
                    if item.removed_at is not None
                ],
            }
        )
