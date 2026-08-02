from typing import Any

from django.db.models import Q
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from umusic.apps.accounts.models import User
from umusic.apps.contexts.models import Activity
from umusic.apps.contexts.services import create_snapshot
from umusic.apps.recommendations.generation_serializers import (
    GeneratedPlaylistSerializer,
    GenerationInputSerializer,
)
from umusic.apps.recommendations.generator import (
    generate_playlist,
    regenerate_playlist,
    replace_track,
)
from umusic.apps.recommendations.models import GeneratedPlaylist, GeneratedPlaylistTrack


def generate_from_data(owner: User, data: dict[str, Any]) -> GeneratedPlaylist:
    activity = (
        Activity.objects.filter(id=data["activity_id"])
        .filter(Q(owner=owner) | Q(owner__isnull=True))
        .first()
    )
    if activity is None:
        raise ValueError("Activity not found")
    snapshot = create_snapshot(
        owner,
        {
            "activity_id": activity.id,
            "geofence_id": data.get("geofence_id"),
            "planned_duration_minutes": data["duration_minutes"],
            "target_energy": data["target_energy"],
            "discovery": data["discovery"],
        },
    )
    return generate_playlist(
        owner,
        activity_kind=activity.kind,
        duration_minutes=int(data["duration_minutes"]),
        target_energy=float(data["target_energy"]),
        discovery=float(data["discovery"]),
        seed=int(data["seed"]),
        context_snapshot=snapshot,
    )


class GeneratePlaylistView(APIView):
    def post(self, request: Request) -> Response:
        serializer = GenerationInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        owner = request.user
        assert isinstance(owner, User)
        try:
            playlist = generate_from_data(owner, serializer.validated_data)
        except ValueError as error:
            return Response({"error": str(error)}, status=404)
        return Response(GeneratedPlaylistSerializer(playlist).data, status=201)


class GeneratedPlaylistDetailView(APIView):
    def get(self, request: Request, playlist_id: str) -> Response:
        playlist = GeneratedPlaylist.objects.filter(id=playlist_id, owner=request.user).first()
        if playlist is None:
            return Response(status=404)
        return Response(GeneratedPlaylistSerializer(playlist).data)


class RegeneratePlaylistView(APIView):
    def post(self, request: Request, playlist_id: str) -> Response:
        source = GeneratedPlaylist.objects.filter(id=playlist_id, owner=request.user).first()
        if source is None:
            return Response(status=404)
        seed = request.data.get("seed")
        owner = request.user
        assert isinstance(owner, User)
        playlist = regenerate_playlist(owner, source, int(seed) if seed is not None else None)
        return Response(GeneratedPlaylistSerializer(playlist).data, status=201)


class ReplaceTrackView(APIView):
    def post(self, request: Request, playlist_id: str) -> Response:
        source = GeneratedPlaylist.objects.filter(id=playlist_id, owner=request.user).first()
        if source is None:
            return Response(status=404)
        try:
            position = int(request.data.get("position"))
        except (TypeError, ValueError):
            return Response({"error": "position is required"}, status=400)
        owner = request.user
        assert isinstance(owner, User)
        try:
            playlist = replace_track(owner, source, position)
        except ValueError as error:
            return Response({"error": str(error)}, status=400)
        return Response(GeneratedPlaylistSerializer(playlist).data, status=201)


class TrackExplanationView(APIView):
    def get(self, request: Request, track_id: str) -> Response:
        item = (
            GeneratedPlaylistTrack.objects.filter(playlist__owner=request.user, track_id=track_id)
            .select_related("playlist", "track")
            .order_by("-playlist__created_at")
            .first()
        )
        if item is None:
            return Response(status=404)
        return Response(
            {
                "track_id": str(item.track_id),
                "score": item.score,
                "model_version": item.playlist.model_version,
                "reasons": item.reasons,
            }
        )
