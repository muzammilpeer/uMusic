import uuid

from django.conf import settings
from django.db import models


class OperationalJob(models.Model):
    class Status(models.TextChoices):
        RUNNING = "running", "Running"
        COMPLETED = "completed", "Completed"
        FAILED = "failed", "Failed"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.CASCADE
    )
    kind = models.CharField(max_length=50)
    idempotency_key = models.CharField(max_length=150, unique=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.RUNNING)
    result = models.JSONField(default=dict)
    error = models.TextField(blank=True)
    attempts = models.PositiveIntegerField(default=1)
    created_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"{self.kind}: {self.status}"
