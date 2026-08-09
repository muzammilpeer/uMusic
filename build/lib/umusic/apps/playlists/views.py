import uuid

from django.db import transaction
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from umusic.apps.accounts.models import User
from umusic.apps.library.models import LibraryMembership
from umusic.apps.library.services import ImportFailure, accessible_tracks, add_library_membership
from umusic.apps.playlists.models import (
    Playlist,
    PlaylistAccess,
    PlaylistInvitation,
    PlaylistTrack,
)
from umusic.apps.playlists.services import (
    audit,
    invite_user,
    playlist_role,
    respond_to_invitation,
    visible_playlists,
)


def _payload(playlist: Playlist, user: User) -> dict[str, object]:
    return {
        "id": str(playlist.id),
        "name": playlist.name,
        "description": playlist.description,
        "revision": playlist.revision,
        "role": playlist_role(playlist, user),
        "owner": playlist.owner.username,
        "tracks": [
            {"id": str(item.track_id), "title": item.track.title, "artist": item.track.artist.name}
            for item in playlist.items.select_related("track", "track__artist")
        ],
    }


class PlaylistCollectionView(APIView):
    def get(self, request: Request) -> Response:
        user = request.user
        assert isinstance(user, User)
        return Response(
            [_payload(item, user) for item in visible_playlists(user).select_related("owner")]
        )

    def post(self, request: Request) -> Response:
        name = str(request.data.get("name", "")).strip()
        if not name:
            return Response({"error": "name is required"}, status=400)
        user = request.user
        assert isinstance(user, User)
        playlist = Playlist.objects.create(
            owner=user, name=name, description=str(request.data.get("description", ""))
        )
        audit(user, "playlist.created", playlist.id)
        return Response(_payload(playlist, user), status=201)


class PlaylistDetailView(APIView):
    def get_object(self, request: Request, playlist_id: str) -> Playlist | None:
        user = request.user
        assert isinstance(user, User)
        return visible_playlists(user).filter(id=playlist_id).select_related("owner").first()

    def get(self, request: Request, playlist_id: str) -> Response:
        playlist = self.get_object(request, playlist_id)
        if playlist is None:
            return Response(status=404)
        user = request.user
        assert isinstance(user, User)
        return Response(_payload(playlist, user))

    def patch(self, request: Request, playlist_id: str) -> Response:
        playlist = self.get_object(request, playlist_id)
        if playlist is None:
            return Response(status=404)
        user = request.user
        assert isinstance(user, User)
        role = playlist_role(playlist, user)
        if role not in {"owner", PlaylistAccess.Role.EDITOR}:
            return Response(status=403)
        try:
            expected_revision = int(request.data.get("revision"))
        except (TypeError, ValueError):
            return Response({"error": "revision is required"}, status=400)
        track_ids = request.data.get("track_ids")
        with transaction.atomic():
            playlist = Playlist.objects.select_for_update().get(id=playlist.id)
            if playlist.revision != expected_revision:
                return Response(
                    {"error": "playlist changed", "revision": playlist.revision}, status=409
                )
            if role == "owner" and "name" in request.data:
                playlist.name = str(request.data["name"]).strip()
            if role == "owner" and "description" in request.data:
                playlist.description = str(request.data["description"])
            playlist.save()
            if track_ids is not None:
                if not isinstance(track_ids, list):
                    return Response({"error": "track_ids must be a list"}, status=400)
                try:
                    normalized_ids = [str(uuid.UUID(str(value))) for value in track_ids]
                except (TypeError, ValueError, AttributeError):
                    return Response({"error": "track_ids contain invalid UUIDs"}, status=400)
                current_ids = set(
                    playlist.items.filter(track_id__in=normalized_ids).values_list(
                        "track_id", flat=True
                    )
                )
                tracks = {
                    str(track.id): track
                    for track in accessible_tracks(user).filter(id__in=normalized_ids)
                }
                missing_current = current_ids - {uuid.UUID(item) for item in tracks}
                if missing_current:
                    for track in playlist.items.filter(track_id__in=missing_current).select_related(
                        "track"
                    ):
                        tracks[str(track.track_id)] = track.track
                if len(tracks) != len(set(normalized_ids)):
                    return Response({"error": "One or more tracks were not found"}, status=400)
                playlist.items.all().delete()
                PlaylistTrack.objects.bulk_create(
                    [
                        PlaylistTrack(playlist=playlist, track=tracks[str(track_id)], position=i)
                        for i, track_id in enumerate(normalized_ids)
                    ]
                )
            playlist.revision += 1
            playlist.save(update_fields=["name", "description", "revision", "updated_at"])
        audit(user, "playlist.updated", playlist.id, {"revision": playlist.revision})
        return Response(_payload(playlist, user))

    def delete(self, request: Request, playlist_id: str) -> Response:
        playlist = self.get_object(request, playlist_id)
        if playlist is None:
            return Response(status=404)
        user = request.user
        assert isinstance(user, User)
        if playlist.owner_id != user.id:
            return Response(status=403)
        audit(user, "playlist.deleted", playlist.id)
        playlist.delete()
        return Response(status=204)


class PlaylistInvitationCollectionView(APIView):
    def get(self, request: Request) -> Response:
        invitations = PlaylistInvitation.objects.filter(
            invited_user=request.user, state=PlaylistInvitation.State.PENDING
        ).select_related("playlist", "invited_by")
        return Response(
            [
                {
                    "id": str(item.id),
                    "playlist_id": str(item.playlist_id),
                    "playlist_name": item.playlist.name,
                    "invited_by": item.invited_by.username if item.invited_by else None,
                    "role": item.role,
                    "expires_at": item.expires_at,
                }
                for item in invitations
            ]
        )

    def post(self, request: Request, playlist_id: str) -> Response:
        playlist = Playlist.objects.filter(id=playlist_id, owner=request.user).first()
        if playlist is None:
            return Response(status=404)
        user = request.user
        assert isinstance(user, User)
        try:
            invitation, token = invite_user(
                user,
                playlist,
                str(request.data.get("identifier", "")).strip(),
                str(request.data.get("role", "viewer")),
            )
        except ValueError:
            return Response({"error": "Invitation could not be created"}, status=400)
        return Response(
            {"id": str(invitation.id), "role": invitation.role, "invite_token": token},
            status=201,
        )


class PlaylistInvitationResponseView(APIView):
    def post(self, request: Request, invitation_id: str) -> Response:
        invitation = PlaylistInvitation.objects.filter(
            id=invitation_id, invited_user=request.user
        ).first()
        if invitation is None:
            return Response(status=404)
        user = request.user
        assert isinstance(user, User)
        accept = request.data.get("action") == "accept"
        if not accept and request.data.get("action") != "decline":
            return Response({"error": "action must be accept or decline"}, status=400)
        try:
            respond_to_invitation(user, invitation, accept)
        except ValueError:
            return Response(status=409)
        return Response(status=204)


class PlaylistMemberCollectionView(APIView):
    def get(self, request: Request, playlist_id: str) -> Response:
        playlist = Playlist.objects.filter(id=playlist_id, owner=request.user).first()
        if playlist is None:
            return Response(status=404)
        members = playlist.access_grants.filter(state=PlaylistAccess.State.ACTIVE).select_related(
            "user"
        )
        return Response(
            [
                {"user_id": str(item.user_id), "username": item.user.username, "role": item.role}
                for item in members
            ]
        )


class PlaylistMemberDetailView(APIView):
    def patch(self, request: Request, playlist_id: str, user_id: str) -> Response:
        grant = PlaylistAccess.objects.filter(
            playlist_id=playlist_id,
            playlist__owner=request.user,
            user_id=user_id,
            state=PlaylistAccess.State.ACTIVE,
        ).first()
        if grant is None:
            return Response(status=404)
        role = str(request.data.get("role", ""))
        if role not in PlaylistAccess.Role.values:
            return Response({"error": "role must be editor or viewer"}, status=400)
        grant.role = role
        grant.save(update_fields=["role", "updated_at"])
        user = request.user
        assert isinstance(user, User)
        audit(user, "playlist.member.role_changed", playlist_id, {"role": role})
        return Response(status=204)

    def delete(self, request: Request, playlist_id: str, user_id: str) -> Response:
        grant = PlaylistAccess.objects.filter(
            playlist_id=playlist_id,
            playlist__owner=request.user,
            user_id=user_id,
            state=PlaylistAccess.State.ACTIVE,
        ).first()
        if grant is None:
            return Response(status=404)
        grant.state = PlaylistAccess.State.REVOKED
        grant.save(update_fields=["state", "updated_at"])
        user = request.user
        assert isinstance(user, User)
        audit(user, "playlist.member.revoked", playlist_id)
        return Response(status=204)


class PlaylistTransferView(APIView):
    def post(self, request: Request, playlist_id: str) -> Response:
        user = request.user
        assert isinstance(user, User)
        target_id = request.data.get("user_id")
        with transaction.atomic():
            playlist = Playlist.objects.select_for_update().filter(
                id=playlist_id, owner=user
            ).first()
            if playlist is None:
                return Response(status=404)
            grant = PlaylistAccess.objects.select_for_update().filter(
                playlist=playlist,
                user_id=target_id,
                state=PlaylistAccess.State.ACTIVE,
            ).first()
            if grant is None:
                return Response({"error": "target must be an active member"}, status=400)
            if Playlist.objects.filter(owner_id=target_id, name=playlist.name).exists():
                return Response(
                    {"error": "target already owns a playlist with this name"}, status=409
                )
            previous_owner = playlist.owner
            playlist.owner_id = target_id
            playlist.revision += 1
            playlist.save(update_fields=["owner", "revision", "updated_at"])
            grant.delete()
            PlaylistAccess.objects.update_or_create(
                playlist=playlist,
                user=previous_owner,
                defaults={
                    "role": PlaylistAccess.Role.EDITOR,
                    "state": PlaylistAccess.State.ACTIVE,
                    "granted_by_id": target_id,
                },
            )
        audit(user, "playlist.ownership.transferred", playlist.id)
        return Response(_payload(playlist, user))

class PlaylistLeaveView(APIView):
    def post(self, request: Request, playlist_id: str) -> Response:
        grant = PlaylistAccess.objects.filter(
            playlist_id=playlist_id,
            user=request.user,
            state=PlaylistAccess.State.ACTIVE,
        ).first()
        if grant is None:
            return Response(status=404)
        grant.state = PlaylistAccess.State.LEFT
        grant.save(update_fields=["state", "updated_at"])
        user = request.user
        assert isinstance(user, User)
        audit(user, "playlist.member.left", playlist_id)
        return Response(status=204)


class SaveSharedTrackView(APIView):
    def post(self, request: Request, playlist_id: str, track_id: str) -> Response:
        user = request.user
        assert isinstance(user, User)
        playlist = visible_playlists(user).filter(id=playlist_id).first()
        item = (
            playlist.items.select_related("track__audio_file").filter(track_id=track_id).first()
            if playlist
            else None
        )
        if playlist is None or item is None:
            return Response(status=404)
        try:
            membership = add_library_membership(
                user, item.track, source=LibraryMembership.Source.ADMIN
            )
        except ImportFailure as error:
            return Response({"error": error.message}, status=409)
        audit(user, "playlist.track.saved", playlist.id, {"track_id": str(membership.track_id)})
        return Response(status=204)
