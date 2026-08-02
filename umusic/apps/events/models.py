import uuid
from typing import Any

from django.conf import settings
from django.db import models

from umusic.apps.contexts.models import ContextSnapshot
from umusic.apps.library.models import Track
from umusic.apps.playback.models import PlaybackSession


class ListeningEvent(models.Model):
    class Type(models.TextChoices):
        STARTED = "started", "Started"
        PROGRESS = "progress", "Progress"
        PAUSED = "paused", "Paused"
        RESUMED = "resumed", "Resumed"
        SEEKED = "seeked", "Seeked"
        COMPLETED = "completed", "Completed"
        SKIPPED = "skipped", "Skipped"
        LIKED = "liked", "Liked"
        DISLIKED = "disliked", "Disliked"
        REPLAYED = "replayed", "Replayed"
        QUEUE_REMOVED = "queue_removed", "Queue removed"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    client_event_id = models.UUIDField()
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    track = models.ForeignKey(Track, on_delete=models.PROTECT, related_name="listening_events")
    playback_session = models.ForeignKey(
        PlaybackSession, null=True, blank=True, on_delete=models.SET_NULL
    )
    context_snapshot = models.ForeignKey(
        ContextSnapshot, null=True, blank=True, on_delete=models.PROTECT
    )
    playback_id = models.UUIDField(help_text="Client-generated ID for one play attempt")
    event_type = models.CharField(max_length=20, choices=Type.choices)
    client_timestamp = models.DateTimeField()
    received_at = models.DateTimeField(auto_now_add=True)
    position_ms = models.PositiveBigIntegerField(default=0)
    duration_ms = models.PositiveBigIntegerField(default=0)
    listened_ms_delta = models.PositiveIntegerField(default=0)
    offline = models.BooleanField(default=False)
    metadata = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ["-received_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["owner", "client_event_id"], name="unique_owner_client_event"
            )
        ]
        indexes = [
            models.Index(fields=["owner", "playback_id", "client_timestamp"]),
            models.Index(fields=["owner", "event_type", "received_at"]),
        ]

    def __str__(self) -> str:
        return f"{self.event_type}: {self.track} at {self.position_ms}ms"

    def save(self, *args: Any, **kwargs: Any) -> None:
        if not self._state.adding:
            raise RuntimeError("Listening events are append-only and cannot be changed")
        super().save(*args, **kwargs)

    def delete(self, *args: Any, **kwargs: Any) -> tuple[int, dict[str, int]]:
        raise RuntimeError("Listening events are retained and cannot be individually deleted")


class PlayFact(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    track = models.ForeignKey(Track, on_delete=models.CASCADE, related_name="play_facts")
    playback_id = models.UUIDField()
    first_event_at = models.DateTimeField()
    last_event_at = models.DateTimeField()
    listening_ms = models.PositiveBigIntegerField(default=0)
    furthest_position_ms = models.PositiveBigIntegerField(default=0)
    duration_ms = models.PositiveBigIntegerField(default=0)
    completed = models.BooleanField(default=False)
    skipped = models.BooleanField(default=False)
    early_skip = models.BooleanField(default=False)
    replayed = models.BooleanField(default=False)
    explicit_feedback = models.SmallIntegerField(default=0)
    event_count = models.PositiveIntegerField(default=0)
    rebuilt_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-last_event_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["owner", "playback_id"], name="unique_owner_playback_fact"
            )
        ]

    def __str__(self) -> str:
        return f"{self.track}: {self.listening_ms}ms listened"
