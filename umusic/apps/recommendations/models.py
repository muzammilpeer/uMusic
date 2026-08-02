import uuid
from typing import Any

from django.conf import settings
from django.db import models

from umusic.apps.contexts.models import ContextSnapshot
from umusic.apps.library.models import Track


class LearningConfiguration(models.Model):
    version = models.CharField(max_length=50, unique=True)
    weights = models.JSONField()
    implicit_half_life_days = models.PositiveSmallIntegerField(default=90)
    global_min_evidence = models.PositiveSmallIntegerField(default=1)
    context_min_evidence = models.PositiveSmallIntegerField(default=3)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return self.version


class Affinity(models.Model):
    class Target(models.TextChoices):
        TRACK = "track", "Track"
        ARTIST = "artist", "Artist"
        GENRE = "genre", "Genre"

    class Context(models.TextChoices):
        GLOBAL = "global", "Global"
        ACTIVITY = "activity", "Activity"
        PLACE = "place", "Place"
        TIME = "time", "Time"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    configuration = models.ForeignKey(LearningConfiguration, on_delete=models.PROTECT)
    target_type = models.CharField(max_length=20, choices=Target.choices)
    target_id = models.CharField(max_length=255)
    target_label = models.CharField(max_length=255)
    context_type = models.CharField(max_length=20, choices=Context.choices)
    context_key = models.CharField(max_length=255, blank=True)
    score = models.DecimalField(max_digits=7, decimal_places=4)
    confidence = models.DecimalField(max_digits=5, decimal_places=4)
    positive_evidence = models.DecimalField(max_digits=10, decimal_places=4, default=0)
    negative_evidence = models.DecimalField(max_digits=10, decimal_places=4, default=0)
    sample_count = models.PositiveIntegerField(default=0)
    explicit_preference = models.SmallIntegerField(default=0)
    evidence = models.JSONField(default=dict)
    last_observation = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-confidence", "-score", "target_label"]
        constraints = [
            models.UniqueConstraint(
                fields=[
                    "owner",
                    "configuration",
                    "target_type",
                    "target_id",
                    "context_type",
                    "context_key",
                ],
                name="unique_versioned_affinity",
            )
        ]

    def __str__(self) -> str:
        return f"{self.target_label} ({self.context_type}): {self.score}"


class LearningRun(models.Model):
    class Status(models.TextChoices):
        RUNNING = "running", "Running"
        COMPLETED = "completed", "Completed"
        FAILED = "failed", "Failed"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    configuration = models.ForeignKey(LearningConfiguration, on_delete=models.PROTECT)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.RUNNING)
    affinity_count = models.PositiveIntegerField(default=0)
    evidence_digest = models.CharField(max_length=64, blank=True)
    error = models.TextField(blank=True)
    started_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-started_at"]

    def __str__(self) -> str:
        return f"{self.configuration.version}: {self.status}"


class GeneratedPlaylist(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    context_snapshot = models.ForeignKey(
        ContextSnapshot, null=True, blank=True, on_delete=models.PROTECT
    )
    source_version = models.ForeignKey(
        "self", null=True, blank=True, on_delete=models.SET_NULL, related_name="derived_versions"
    )
    activity_kind = models.CharField(max_length=20)
    geofence_reference = models.UUIDField(null=True, blank=True)
    requested_duration_minutes = models.PositiveSmallIntegerField()
    actual_duration_ms = models.PositiveBigIntegerField(default=0)
    target_energy = models.DecimalField(max_digits=3, decimal_places=2)
    discovery = models.DecimalField(max_digits=3, decimal_places=2)
    seed = models.BigIntegerField()
    model_version = models.CharField(max_length=50)
    input_digest = models.CharField(max_length=64)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"{self.activity_kind} {self.requested_duration_minutes} min ({self.seed})"

    def save(self, *args: Any, **kwargs: Any) -> None:
        if not self._state.adding:
            raise RuntimeError("Generated playlist versions are immutable")
        super().save(*args, **kwargs)


class GeneratedPlaylistTrack(models.Model):
    playlist = models.ForeignKey(GeneratedPlaylist, on_delete=models.CASCADE, related_name="items")
    track = models.ForeignKey(Track, on_delete=models.PROTECT)
    position = models.PositiveIntegerField()
    score = models.DecimalField(max_digits=8, decimal_places=5)
    target_energy = models.DecimalField(max_digits=3, decimal_places=2)
    reasons = models.JSONField(default=list)

    class Meta:
        ordering = ["position"]
        constraints = [
            models.UniqueConstraint(
                fields=["playlist", "position"], name="unique_generated_playlist_position"
            ),
            models.UniqueConstraint(
                fields=["playlist", "track"], name="unique_generated_playlist_track"
            ),
        ]

    def __str__(self) -> str:
        return f"{self.playlist_id}[{self.position}] {self.track}"

    def save(self, *args: Any, **kwargs: Any) -> None:
        if not self._state.adding:
            raise RuntimeError("Generated playlist items are immutable")
        super().save(*args, **kwargs)
