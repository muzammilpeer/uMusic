from django.db import transaction
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from umusic.apps.library.models import Track
from umusic.apps.playlists.models import Playlist, PlaylistTrack


def _payload(playlist: Playlist) -> dict[str, object]:
    return {
        "id": str(playlist.id),
        "name": playlist.name,
        "description": playlist.description,
        "tracks": [
            {"id": str(item.track_id), "title": item.track.title, "artist": item.track.artist.name}
            for item in playlist.items.select_related("track", "track__artist")
        ],
    }


class PlaylistCollectionView(APIView):
    def get(self, request: Request) -> Response:
        return Response([_payload(item) for item in Playlist.objects.filter(owner=request.user)])

    def post(self, request: Request) -> Response:
        name = str(request.data.get("name", "")).strip()
        if not name:
            return Response({"error": "name is required"}, status=400)
        playlist = Playlist.objects.create(
            owner=request.user, name=name, description=str(request.data.get("description", ""))
        )
        return Response(_payload(playlist), status=201)


class PlaylistDetailView(APIView):
    def get_object(self, request: Request, playlist_id: str) -> Playlist | None:
        return Playlist.objects.filter(id=playlist_id, owner=request.user).first()

    def get(self, request: Request, playlist_id: str) -> Response:
        playlist = self.get_object(request, playlist_id)
        return Response(_payload(playlist)) if playlist else Response(status=404)

    def patch(self, request: Request, playlist_id: str) -> Response:
        playlist = self.get_object(request, playlist_id)
        if playlist is None:
            return Response(status=404)
        if "name" in request.data:
            playlist.name = str(request.data["name"]).strip()
        if "description" in request.data:
            playlist.description = str(request.data["description"])
        track_ids = request.data.get("track_ids")
        with transaction.atomic():
            playlist.save()
            if track_ids is not None:
                if not isinstance(track_ids, list):
                    return Response({"error": "track_ids must be a list"}, status=400)
                tracks = {
                    str(track.id): track
                    for track in Track.objects.filter(id__in=track_ids, is_active=True)
                }
                if len(tracks) != len(set(track_ids)):
                    return Response({"error": "One or more tracks were not found"}, status=400)
                playlist.items.all().delete()
                PlaylistTrack.objects.bulk_create(
                    [
                        PlaylistTrack(playlist=playlist, track=tracks[str(track_id)], position=i)
                        for i, track_id in enumerate(track_ids)
                    ]
                )
        return Response(_payload(playlist))

    def delete(self, request: Request, playlist_id: str) -> Response:
        playlist = self.get_object(request, playlist_id)
        if playlist is None:
            return Response(status=404)
        playlist.delete()
        return Response(status=204)
