import hashlib
import secrets
import uuid

from django.conf import settings
from django.contrib.auth.models import AbstractUser
from django.db import models


class User(AbstractUser):
    """Project user model, established before the first migration."""

    storage_quota_bytes = models.PositiveBigIntegerField(default=5 * 1024 * 1024 * 1024)


class Device(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    name = models.CharField(max_length=120)
    platform = models.CharField(max_length=30, default="ios")
    token_prefix = models.CharField(max_length=12, unique=True)
    token_hash = models.CharField(max_length=64)
    scopes = models.JSONField(default=list)
    last_seen_at = models.DateTimeField(null=True, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"{self.name} ({self.platform})"

    @classmethod
    def issue(cls, *, owner: User, name: str, platform: str = "ios") -> tuple["Device", str]:
        secret = secrets.token_urlsafe(32)
        prefix = secrets.token_hex(6)
        device = cls.objects.create(
            owner=owner,
            name=name,
            platform=platform,
            token_prefix=prefix,
            token_hash=hashlib.sha256(secret.encode()).hexdigest(),
            scopes=["library:read", "playback:write", "sync:read", "events:write"],
        )
        return device, f"{prefix}.{secret}"

    def matches(self, secret: str) -> bool:
        return secrets.compare_digest(self.token_hash, hashlib.sha256(secret.encode()).hexdigest())
