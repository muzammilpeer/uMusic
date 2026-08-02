import uuid

from django.db import transaction
from rest_framework import status
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from umusic.apps.accounts.models import Device, User
from umusic.apps.contexts.models import ContextSnapshot
from umusic.apps.library.api_views import track_payload
from umusic.apps.library.models import Track
from umusic.apps.playback.models import PlaybackSession, QueueItem
from umusic.apps.recommendations.generator import regenerate_playlist
from umusic.apps.recommendations.models import GeneratedPlaylist
from umusic.apps.sync.views import manifest_entry


def _normalize_track_ids(values: list[object]) -> list[str] | None:
    try:
        return [str(uuid.UUID(str(value))) for value in values]
    except (ValueError, TypeError, AttributeError):
        return None


def _payload(session: PlaybackSession) -> dict[str, object]:
    items = session.items.select_related("track", "track__artist")
    return {
        "id": str(session.id),
        "status": session.status,
        "current_track_id": str(session.current_track_id) if session.current_track_id else None,
        "current_index": session.current_index,
        "position_ms": session.position_ms,
        "revision": session.revision,
        "queue": [
            {
                "track_id": str(item.track_id),
                "title": item.track.title,
                "artist": item.track.artist.name,
                "position": item.position,
            }
            for item in items
        ],
    }


class SessionCollectionView(APIView):
    def post(self, request: Request) -> Response:
        track_ids = request.data.get("track_ids", [])
        if not isinstance(track_ids, list):
            return Response({"error": "track_ids must be a list"}, status=400)
        normalized_ids = _normalize_track_ids(track_ids)
        if normalized_ids is None:
            return Response({"error": "track_ids must contain valid UUIDs"}, status=400)
        tracks = {
            str(track.id): track
            for track in Track.objects.filter(id__in=normalized_ids, is_active=True)
        }
        if len(tracks) != len(set(normalized_ids)):
            return Response({"error": "One or more tracks were not found"}, status=400)
        with transaction.atomic():
            context_id = request.data.get("context_snapshot_id")
            context = None
            if context_id:
                context = ContextSnapshot.objects.filter(id=context_id, owner=request.user).first()
                if context is None:
                    return Response({"error": "Context snapshot not found"}, status=400)
            session = PlaybackSession.objects.create(owner=request.user, context_snapshot=context)
            QueueItem.objects.bulk_create(
                [
                    QueueItem(session=session, track=tracks[track_id], position=i)
                    for i, track_id in enumerate(normalized_ids)
                ]
            )
            if normalized_ids:
                session.current_track = tracks[normalized_ids[0]]
                session.save(update_fields=["current_track", "updated_at"])
        return Response(_payload(session), status=status.HTTP_201_CREATED)


class SessionDetailView(APIView):
    def get(self, request: Request, session_id: str) -> Response:
        session = PlaybackSession.objects.filter(id=session_id, owner=request.user).first()
        return Response(_payload(session)) if session else Response(status=404)

    def patch(self, request: Request, session_id: str) -> Response:
        session = PlaybackSession.objects.filter(id=session_id, owner=request.user).first()
        if session is None:
            return Response(status=404)
        for field in ("current_index", "position_ms", "status"):
            if field in request.data:
                setattr(session, field, request.data[field])
        if "current_track_id" in request.data:
            session.current_track = Track.objects.filter(
                id=request.data["current_track_id"], is_active=True
            ).first()
        session.revision += 1
        session.save()
        return Response(_payload(session))


class QueueView(APIView):
    def patch(self, request: Request, session_id: str) -> Response:
        session = PlaybackSession.objects.filter(id=session_id, owner=request.user).first()
        if session is None:
            return Response(status=404)
        track_ids = request.data.get("track_ids")
        if not isinstance(track_ids, list):
            return Response({"error": "track_ids must be a list"}, status=400)
        normalized_ids = _normalize_track_ids(track_ids)
        if normalized_ids is None:
            return Response({"error": "track_ids must contain valid UUIDs"}, status=400)
        tracks = {
            str(track.id): track
            for track in Track.objects.filter(id__in=normalized_ids, is_active=True)
        }
        if len(tracks) != len(set(normalized_ids)):
            return Response({"error": "One or more tracks were not found"}, status=400)
        with transaction.atomic():
            session.items.all().delete()
            QueueItem.objects.bulk_create(
                [
                    QueueItem(session=session, track=tracks[track_id], position=i)
                    for i, track_id in enumerate(normalized_ids)
                ]
            )
            session.current_index = min(session.current_index, max(0, len(normalized_ids) - 1))
            session.current_track = (
                tracks[normalized_ids[session.current_index]] if normalized_ids else None
            )
            session.revision += 1
            session.save()
        return Response(_payload(session))


class ContinuationView(APIView):
    def post(self, request: Request, session_id: str) -> Response:
        session = PlaybackSession.objects.filter(id=session_id, owner=request.user).first()
        if session is None:
            return Response(status=404)
        groups = [
            request.data.get("played_track_ids", []),
            request.data.get("remaining_track_ids", []),
            request.data.get("cached_track_ids", []),
        ]
        if any(not isinstance(group, list) for group in groups):
            return Response({"error": "Track exclusions must be lists"}, status=400)
        excluded_values = [value for group in groups for value in group]
        excluded = {str(value).lower() for value in excluded_values}
        try:
            desired = min(25, max(1, int(request.data.get("desired_count", 10))))
        except (TypeError, ValueError):
            return Response({"error": "desired_count must be an integer"}, status=400)
        source_id = request.data.get("recommendation_version_id")
        source = GeneratedPlaylist.objects.filter(owner=request.user, id=source_id).first()
        if source is None:
            source = GeneratedPlaylist.objects.filter(
                owner=request.user, context_snapshot=session.context_snapshot
            ).first()
        if source is None:
            return Response({"error": "No recommendation version for this session"}, status=409)
        owner = request.user
        assert isinstance(owner, User)
        regenerated = regenerate_playlist(owner, source)
        selected = [
            item
            for item in regenerated.items.select_related(
                "track", "track__artist", "track__album", "track__audio_file"
            )
            if str(item.track_id) not in excluded
        ][:desired]
        device = request.auth if isinstance(request.auth, Device) else None
        tracks = []
        for position, item in enumerate(selected):
            payload = (
                manifest_entry(request, item.track, position=position, device_id=device.id)
                if device
                else track_payload(item.track)
            )
            tracks.append({**payload, "reasons": item.reasons})
        return Response(
            {
                "recommendation_version_id": str(regenerated.id),
                "tracks": tracks,
            }
        )
