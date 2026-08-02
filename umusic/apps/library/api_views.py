from django.db.models import Q
from rest_framework.pagination import PageNumberPagination
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from umusic.apps.library.models import Album, Artist, Track
from umusic.apps.sync.views import signed_download_url


def track_payload(track: Track, request: Request | None = None) -> dict[str, object]:
    payload: dict[str, object] = {
        "id": str(track.id),
        "title": track.title,
        "artist": {"id": str(track.artist_id), "name": track.artist.name},
        "album": ({"id": str(track.album_id), "title": track.album.title} if track.album else None),
        "duration_ms": track.audio_file.duration_ms,
        "genres": track.genres,
        "energy": float(track.energy) if track.energy is not None else None,
        "stream_path": f"/api/v1/tracks/{track.id}/stream/",
        "updated_at": track.updated_at,
    }
    device = getattr(request, "auth", None) if request is not None else None
    if device is not None and getattr(device, "id", None):
        payload["stream_url"] = signed_download_url(
            request, track_id=track.id, device_id=device.id
        )
    return payload


class TrackPagination(PageNumberPagination):
    page_size = 50
    page_size_query_param = "page_size"
    max_page_size = 100


class TrackCollectionView(APIView):
    def get(self, request: Request) -> Response:
        tracks = Track.objects.filter(is_active=True).select_related(
            "artist", "album", "audio_file"
        )
        query = str(request.query_params.get("q", "")).strip()
        if query:
            tracks = tracks.filter(
                Q(title__icontains=query)
                | Q(artist__name__icontains=query)
                | Q(album__title__icontains=query)
            )
        paginator = TrackPagination()
        page = paginator.paginate_queryset(tracks, request, view=self)
        return paginator.get_paginated_response(
            [track_payload(track, request) for track in page]
        )


class TrackDetailView(APIView):
    def get(self, request: Request, track_id: str) -> Response:
        track = (
            Track.objects.filter(id=track_id, is_active=True)
            .select_related("artist", "album", "audio_file")
            .first()
        )
        return Response(track_payload(track, request)) if track else Response(status=404)

    def delete(self, request: Request, track_id: str) -> Response:
        if not request.user.is_superuser:
            return Response(
                {"detail": "Only a server administrator can delete library music."},
                status=403,
            )
        track = (
            Track.objects.filter(id=track_id, is_active=True)
            .select_related("artist", "audio_file")
            .first()
        )
        if not track:
            return Response(status=404)
        from umusic.apps.library.services import remove_track_from_library

        remove_track_from_library(track, request.user)
        return Response(status=204)


class ArtistCollectionView(APIView):
    def get(self, request: Request) -> Response:
        artists = Artist.objects.filter(tracks__is_active=True).distinct()[:500]
        return Response([{"id": str(item.id), "name": item.name} for item in artists])


class AlbumCollectionView(APIView):
    def get(self, request: Request) -> Response:
        albums = (
            Album.objects.filter(tracks__is_active=True)
            .select_related("album_artist")
            .distinct()[:500]
        )
        return Response(
            [
                {
                    "id": str(item.id),
                    "title": item.title,
                    "artist": item.album_artist.name if item.album_artist else None,
                    "year": item.year,
                }
                for item in albums
            ]
        )
