import uuid
from typing import Any

from django.conf import settings
from django.db import models


class Activity(models.Model):
    class Kind(models.TextChoices):
        CYCLING = "cycling", "Cycling"
        RUNNING = "running", "Running"
        GYM = "gym", "Gym"
        FOCUS = "focus", "Focus"
        WALKING = "walking", "Walking"
        RELAX = "relax", "Relax"
        COMMUTE = "commute", "Commute"
        CUSTOM = "custom", "Custom"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.CASCADE
    )
    name = models.CharField(max_length=100)
    slug = models.SlugField(max_length=100)
    kind = models.CharField(max_length=20, choices=Kind.choices)
    phase_curve = models.JSONField(default=list, blank=True)
    is_preset = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["name"]
        constraints = [
            models.UniqueConstraint(fields=["owner", "slug"], name="unique_owner_activity_slug")
        ]

    def __str__(self) -> str:
        return self.name


class Geofence(models.Model):
    class Privacy(models.TextChoices):
        MANUAL = "manual", "Manual selection only"
        LOCATION = "location", "Allow device location matching"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    name = models.CharField(max_length=100)
    latitude = models.DecimalField(max_digits=9, decimal_places=6)
    longitude = models.DecimalField(max_digits=9, decimal_places=6)
    radius_m = models.PositiveIntegerField(default=200)
    privacy = models.CharField(max_length=20, choices=Privacy.choices, default=Privacy.MANUAL)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["name"]
        constraints = [
            models.UniqueConstraint(fields=["owner", "name"], name="unique_owner_place_name"),
            models.CheckConstraint(
                condition=models.Q(radius_m__gte=25, radius_m__lte=100_000),
                name="valid_geofence_radius",
            ),
        ]

    def __str__(self) -> str:
        return self.name


class ContextSnapshot(models.Model):
    class Phase(models.TextChoices):
        WARMUP = "warmup", "Warm-up"
        SUSTAIN = "sustain", "Sustain"
        RECOVERY = "recovery", "Recovery"
        COOLDOWN = "cooldown", "Cooldown"
        REST = "rest", "Rest"
        STEADY = "steady", "Steady"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    activity = models.ForeignKey(Activity, null=True, blank=True, on_delete=models.SET_NULL)
    activity_name = models.CharField(max_length=100)
    activity_kind = models.CharField(max_length=20, choices=Activity.Kind.choices)
    phase = models.CharField(max_length=20, choices=Phase.choices, default=Phase.STEADY)
    geofence_reference = models.UUIDField(null=True, blank=True)
    geofence_name = models.CharField(max_length=100, blank=True)
    planned_duration_minutes = models.PositiveSmallIntegerField(default=60)
    target_energy = models.DecimalField(max_digits=3, decimal_places=2, default=0.50)
    discovery = models.DecimalField(max_digits=3, decimal_places=2, default=0.20)
    time_bucket = models.CharField(max_length=20)
    is_weekend = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        place = f" at {self.geofence_name}" if self.geofence_name else ""
        return f"{self.activity_name}{place}"

    def save(self, *args: Any, **kwargs: Any) -> None:
        if not self._state.adding:
            raise RuntimeError("Context snapshots are immutable")
        super().save(*args, **kwargs)


class ContextForgetRecord(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    geofence_reference = models.UUIDField()
    forgotten_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-forgotten_at"]

    def __str__(self) -> str:
        return f"Forget {self.geofence_reference} at {self.forgotten_at}"
