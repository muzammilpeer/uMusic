import hashlib
import secrets
import uuid
from datetime import datetime
from typing import Any

from django.conf import settings
from django.db import models

from umusic.apps.library.models import Track


class Playlist(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    name = models.CharField(max_length=150)
    description = models.TextField(blank=True)
    revision = models.PositiveBigIntegerField(default=1)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["name"]
        constraints = [
            models.UniqueConstraint(fields=["owner", "name"], name="unique_owner_playlist_name")
        ]

    def __str__(self) -> str:
        return self.name


class PlaylistTrack(models.Model):
    playlist = models.ForeignKey(Playlist, on_delete=models.CASCADE, related_name="items")
    track = models.ForeignKey(Track, on_delete=models.CASCADE)
    position = models.PositiveIntegerField()

    class Meta:
        ordering = ["position"]
        constraints = [
            models.UniqueConstraint(
                fields=["playlist", "position"], name="unique_playlist_position"
            )
        ]

    def __str__(self) -> str:
        return f"{self.playlist}[{self.position}] {self.track}"


class PlaylistAccess(models.Model):
    class Role(models.TextChoices):
        EDITOR = "editor", "Editor"
        VIEWER = "viewer", "Viewer"

    class State(models.TextChoices):
        ACTIVE = "active", "Active"
        REVOKED = "revoked", "Revoked"
        LEFT = "left", "Left"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    playlist = models.ForeignKey(Playlist, on_delete=models.CASCADE, related_name="access_grants")
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="playlist_access"
    )
    role = models.CharField(max_length=16, choices=Role.choices)
    state = models.CharField(max_length=16, choices=State.choices, default=State.ACTIVE)
    granted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        on_delete=models.SET_NULL,
        related_name="playlist_access_granted",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["playlist", "user"], name="unique_playlist_user_access"
            )
        ]
        indexes = [models.Index(fields=["user", "state"], name="playlist_user_state_idx")]

    def __str__(self) -> str:
        return f"{self.playlist}: {self.user} ({self.role}, {self.state})"


class PlaylistInvitation(models.Model):
    class State(models.TextChoices):
        PENDING = "pending", "Pending"
        ACCEPTED = "accepted", "Accepted"
        DECLINED = "declined", "Declined"
        REVOKED = "revoked", "Revoked"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    playlist = models.ForeignKey(Playlist, on_delete=models.CASCADE, related_name="invitations")
    invited_user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="playlist_invitations"
    )
    invited_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        on_delete=models.SET_NULL,
        related_name="playlist_invitations_sent",
    )
    role = models.CharField(max_length=16, choices=PlaylistAccess.Role.choices)
    token_prefix = models.CharField(max_length=12, unique=True)
    token_hash = models.CharField(max_length=64)
    state = models.CharField(max_length=16, choices=State.choices, default=State.PENDING)
    expires_at = models.DateTimeField()
    responded_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(
                fields=["invited_user", "state"], name="playlist_invitee_state_idx"
            )
        ]

    def __str__(self) -> str:
        return f"{self.playlist}: invite {self.invited_user} ({self.state})"

    @classmethod
    def issue(
        cls,
        *,
        playlist: Playlist,
        invited_user: Any,
        invited_by: Any,
        role: str,
        expires_at: datetime,
    ) -> tuple["PlaylistInvitation", str]:
        secret = secrets.token_urlsafe(32)
        prefix = secrets.token_hex(6)
        invitation = cls.objects.create(
            playlist=playlist,
            invited_user=invited_user,
            invited_by=invited_by,
            role=role,
            token_prefix=prefix,
            token_hash=hashlib.sha256(secret.encode()).hexdigest(),
            expires_at=expires_at,
        )
        return invitation, f"{prefix}.{secret}"

    def matches(self, secret: str) -> bool:
        return secrets.compare_digest(
            self.token_hash, hashlib.sha256(secret.encode()).hexdigest()
        )
