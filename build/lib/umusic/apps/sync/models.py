import uuid

from django.conf import settings
from django.db import models

from umusic.apps.accounts.models import Device
from umusic.apps.recommendations.models import GeneratedPlaylist


class SyncPlan(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    device = models.ForeignKey(Device, on_delete=models.CASCADE)
    playlist = models.ForeignKey(GeneratedPlaylist, on_delete=models.PROTECT)
    manifest_version = models.PositiveIntegerField(default=1)
    acknowledged_at = models.DateTimeField(null=True, blank=True)
    acknowledgement = models.JSONField(default=dict)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"{self.device}: {self.playlist_id}"
