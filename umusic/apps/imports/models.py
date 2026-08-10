import uuid

from django.conf import settings
from django.db import models

from umusic.apps.library.models import Track


class AdapterJob(models.Model):
    class Adapter(models.TextChoices):
        FOLDER = "folder", "Server folder"
        TASTE = "taste", "Taste metadata"
        YOUTUBE = "youtube", "YouTube audio"
        REMOTE = "remote", "Remote URL batch"

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        RUNNING = "running", "Running"
        COMPLETED = "completed", "Completed"
        PARTIAL = "partial", "Completed with errors"
        FAILED = "failed", "Failed"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    adapter = models.CharField(max_length=20, choices=Adapter.choices)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    request = models.JSONField(default=dict)
    idempotency_key = models.UUIDField(null=True, blank=True)
    provenance = models.JSONField(default=dict)
    operator_attested = models.BooleanField(default=False)
    imported_count = models.PositiveIntegerField(default=0)
    error = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["owner", "idempotency_key"],
                condition=models.Q(idempotency_key__isnull=False),
                name="import_job_owner_idempotency_key",
            )
        ]

    def __str__(self) -> str:
        return f"{self.adapter}: {self.status}"


class RemoteImportItem(models.Model):
    class Kind(models.TextChoices):
        DIRECT_MP3 = "direct_mp3", "Direct MP3"
        YOUTUBE = "youtube", "YouTube"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    job = models.ForeignKey(AdapterJob, on_delete=models.CASCADE, related_name="remote_items")
    position = models.PositiveIntegerField()
    kind = models.CharField(max_length=20, choices=Kind.choices)
    source_url = models.URLField(max_length=2000)
    source_host = models.CharField(max_length=255)
    status = models.CharField(max_length=20, choices=AdapterJob.Status.choices, default="pending")
    imported = models.BooleanField(default=False)
    error = models.CharField(max_length=500, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["position"]
        constraints = [
            models.UniqueConstraint(fields=["job", "position"], name="remote_item_job_position")
        ]

    def __str__(self) -> str:
        return f"{self.position}: {self.kind} ({self.status})"


class TasteCandidate(models.Model):
    class State(models.TextChoices):
        EXACT = "exact", "Exact"
        PROBABLE = "probable", "Probable"
        UNMATCHED = "unmatched", "Unmatched"
        REJECTED = "rejected", "Rejected"
        CONFIRMED = "confirmed", "Confirmed"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    job = models.ForeignKey(AdapterJob, on_delete=models.CASCADE, related_name="candidates")
    artist = models.CharField(max_length=255)
    title = models.CharField(max_length=255)
    duration_ms = models.PositiveBigIntegerField(null=True, blank=True)
    matched_track = models.ForeignKey(Track, null=True, blank=True, on_delete=models.SET_NULL)
    state = models.CharField(max_length=20, choices=State.choices)
    confidence = models.DecimalField(max_digits=5, decimal_places=4, default=0)
    audio_acquisition_authorized = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:
        return f"{self.artist} — {self.title} ({self.state})"
