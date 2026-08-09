from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.http import HttpRequest, HttpResponse
from django.shortcuts import get_object_or_404, redirect, render

from umusic.apps.accounts.models import User
from umusic.apps.library.models import LibraryMembership
from umusic.apps.library.services import ImportFailure, add_library_membership
from umusic.apps.playlists.models import Playlist, PlaylistAccess, PlaylistInvitation
from umusic.apps.playlists.services import invite_user, playlist_role, respond_to_invitation, visible_playlists


@login_required
def sharing_home(request: HttpRequest) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    playlists = visible_playlists(user).select_related("owner")
    invitations = PlaylistInvitation.objects.filter(
        invited_user=user, state=PlaylistInvitation.State.PENDING
    ).select_related("playlist", "invited_by")
    return render(
        request,
        "playlists/sharing.html",
        {"playlists": playlists, "invitations": invitations},
    )


@login_required
def sharing_detail(request: HttpRequest, playlist_id: str) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    playlist = get_object_or_404(
        visible_playlists(user).select_related("owner"), id=playlist_id
    )
    if request.method == "POST":
        action = request.POST.get("action")
        try:
            if action == "invite" and playlist.owner_id == user.id:
                invite_user(
                    user,
                    playlist,
                    request.POST.get("identifier", "").strip(),
                    request.POST.get("role", PlaylistAccess.Role.VIEWER),
                )
                messages.success(request, "Invitation created.")
            elif action == "save":
                item = get_object_or_404(playlist.items.select_related("track"), track_id=request.POST.get("track_id"))
                add_library_membership(user, item.track, LibraryMembership.Source.ADMIN)
                messages.success(request, "Song saved to My Library.")
            elif action == "leave" and playlist.owner_id != user.id:
                PlaylistAccess.objects.filter(
                    playlist=playlist, user=user, state=PlaylistAccess.State.ACTIVE
                ).update(state=PlaylistAccess.State.LEFT)
                return redirect("playlist-sharing")
            elif action == "revoke" and playlist.owner_id == user.id:
                PlaylistAccess.objects.filter(
                    playlist=playlist,
                    user_id=request.POST.get("user_id"),
                    state=PlaylistAccess.State.ACTIVE,
                ).update(state=PlaylistAccess.State.REVOKED)
                messages.success(request, "Access revoked.")
            else:
                messages.error(request, "That action is not allowed.")
        except (ValueError, ImportFailure):
            messages.error(request, "The request could not be completed.")
        return redirect("playlist-sharing-detail", playlist_id=playlist.id)
    return render(
        request,
        "playlists/detail.html",
        {
            "playlist": playlist,
            "role": playlist_role(playlist, user),
            "members": playlist.access_grants.filter(
                state=PlaylistAccess.State.ACTIVE
            ).select_related("user"),
        },
    )


@login_required
def invitation_response(request: HttpRequest, invitation_id: str) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    invitation = get_object_or_404(PlaylistInvitation, id=invitation_id, invited_user=user)
    if request.method == "POST":
        try:
            respond_to_invitation(user, invitation, request.POST.get("action") == "accept")
        except ValueError:
            messages.error(request, "This invitation is no longer available.")
    return redirect("playlist-sharing")
