from datetime import timedelta
from typing import Any

from django.db.models import Q, QuerySet
from django.utils import timezone

from umusic.apps.accounts.models import User
from umusic.apps.library.models import AuditEvent
from umusic.apps.playlists.models import Playlist, PlaylistAccess, PlaylistInvitation


def visible_playlists(user: User) -> QuerySet[Playlist]:
    return Playlist.objects.filter(
        Q(owner=user)
        | Q(
            access_grants__user=user,
            access_grants__state=PlaylistAccess.State.ACTIVE,
        )
    ).distinct()


def playlist_role(playlist: Playlist, user: User) -> str | None:
    if playlist.owner_id == user.id:
        return "owner"
    return (
        PlaylistAccess.objects.filter(
            playlist=playlist, user=user, state=PlaylistAccess.State.ACTIVE
        ).values_list("role", flat=True).first()
    )


def audit(actor: User, action: str, target: object, metadata: dict[str, Any] | None = None) -> None:
    AuditEvent.objects.create(
        actor=actor,
        action=action,
        target_type="playlist",
        target_id=str(target),
        metadata=metadata or {},
    )


def invite_user(
    owner: User, playlist: Playlist, identifier: str, role: str
) -> tuple[PlaylistInvitation, str]:
    if playlist.owner_id != owner.id or role not in PlaylistAccess.Role.values:
        raise ValueError("Invitation is not allowed")
    invited = User.objects.filter(is_active=True).filter(
        Q(username__iexact=identifier) | Q(email__iexact=identifier)
    ).first()
    if invited is None or invited.id == owner.id:
        raise ValueError("Invitation target is unavailable")
    PlaylistInvitation.objects.filter(
        playlist=playlist,
        invited_user=invited,
        state=PlaylistInvitation.State.PENDING,
    ).update(state=PlaylistInvitation.State.REVOKED, responded_at=timezone.now())
    invitation, token = PlaylistInvitation.issue(
        playlist=playlist,
        invited_user=invited,
        invited_by=owner,
        role=role,
        expires_at=timezone.now() + timedelta(days=7),
    )
    audit(owner, "playlist.invitation.created", playlist.id, {"role": role})
    return invitation, token


def respond_to_invitation(user: User, invitation: PlaylistInvitation, accept: bool) -> None:
    if (
        invitation.invited_user_id != user.id
        or invitation.state != PlaylistInvitation.State.PENDING
        or invitation.expires_at <= timezone.now()
    ):
        raise ValueError("Invitation is unavailable")
    invitation.state = (
        PlaylistInvitation.State.ACCEPTED if accept else PlaylistInvitation.State.DECLINED
    )
    invitation.responded_at = timezone.now()
    invitation.save(update_fields=["state", "responded_at"])
    if accept:
        PlaylistAccess.objects.update_or_create(
            playlist=invitation.playlist,
            user=user,
            defaults={
                "role": invitation.role,
                "state": PlaylistAccess.State.ACTIVE,
                "granted_by": invitation.invited_by,
            },
        )
    audit(
        user,
        "playlist.invitation.accepted" if accept else "playlist.invitation.declined",
        invitation.playlist_id,
    )
