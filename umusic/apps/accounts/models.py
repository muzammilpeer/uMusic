import hashlib
import secrets
import uuid
from datetime import datetime

from django.conf import settings
from django.contrib.auth.models import AbstractUser
from django.db import models


class User(AbstractUser):
    """Project user model, established before the first migration."""

    public_id = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
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


class DeviceAccessToken(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    device = models.ForeignKey(Device, on_delete=models.CASCADE, related_name="access_tokens")
    token_prefix = models.CharField(max_length=16, unique=True)
    token_hash = models.CharField(max_length=64)
    expires_at = models.DateTimeField(db_index=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:
        return f"Access token for {self.device_id}"

    @classmethod
    def issue(cls, *, device: Device, expires_at: datetime) -> tuple["DeviceAccessToken", str]:
        secret = secrets.token_urlsafe(32)
        prefix = f"a_{secrets.token_hex(6)}"
        token = cls.objects.create(
            device=device,
            token_prefix=prefix,
            token_hash=hashlib.sha256(secret.encode()).hexdigest(),
            expires_at=expires_at,
        )
        return token, f"{prefix}.{secret}"

    def matches(self, secret: str) -> bool:
        return secrets.compare_digest(self.token_hash, hashlib.sha256(secret.encode()).hexdigest())


class DeviceRefreshToken(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    device = models.ForeignKey(Device, on_delete=models.CASCADE, related_name="refresh_tokens")
    token_prefix = models.CharField(max_length=16, unique=True)
    token_hash = models.CharField(max_length=64)
    expires_at = models.DateTimeField(db_index=True)
    used_at = models.DateTimeField(null=True, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
    replaced_by = models.OneToOneField(
        "self", null=True, blank=True, on_delete=models.SET_NULL, related_name="replaces"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:
        return f"Refresh token for {self.device_id}"

    @classmethod
    def issue(cls, *, device: Device, expires_at: datetime) -> tuple["DeviceRefreshToken", str]:
        secret = secrets.token_urlsafe(32)
        prefix = f"r_{secrets.token_hex(6)}"
        token = cls.objects.create(
            device=device,
            token_prefix=prefix,
            token_hash=hashlib.sha256(secret.encode()).hexdigest(),
            expires_at=expires_at,
        )
        return token, f"{prefix}.{secret}"

    def matches(self, secret: str) -> bool:
        return secrets.compare_digest(self.token_hash, hashlib.sha256(secret.encode()).hexdigest())
