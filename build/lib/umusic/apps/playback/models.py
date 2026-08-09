import uuid

from django.conf import settings
from django.db import models

from umusic.apps.contexts.models import ContextSnapshot
from umusic.apps.library.models import Track


class PlaybackSession(models.Model):
    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        ENDED = "ended", "Ended"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.ACTIVE)
    current_track = models.ForeignKey(Track, null=True, blank=True, on_delete=models.SET_NULL)
    context_snapshot = models.ForeignKey(
        ContextSnapshot, null=True, blank=True, on_delete=models.PROTECT
    )
    current_index = models.PositiveIntegerField(default=0)
    position_ms = models.PositiveBigIntegerField(default=0)
    revision = models.PositiveIntegerField(default=1)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-updated_at"]

    def __str__(self) -> str:
        return f"{self.owner}: {self.id}"


class QueueItem(models.Model):
    session = models.ForeignKey(PlaybackSession, on_delete=models.CASCADE, related_name="items")
    track = models.ForeignKey(Track, on_delete=models.CASCADE)
    position = models.PositiveIntegerField()
    added_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["position"]
        constraints = [
            models.UniqueConstraint(fields=["session", "position"], name="unique_queue_position")
        ]

    def __str__(self) -> str:
        return f"{self.session_id}[{self.position}] {self.track}"
