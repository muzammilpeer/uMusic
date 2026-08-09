from typing import Any

from django.db.models import Q
from django.utils import timezone

from umusic.apps.accounts.models import User
from umusic.apps.contexts.models import Activity, ContextForgetRecord, ContextSnapshot, Geofence
from umusic.apps.library.models import AuditEvent


def _time_bucket(hour: int) -> str:
    if hour < 6:
        return "night"
    if hour < 12:
        return "morning"
    if hour < 18:
        return "afternoon"
    return "evening"


def create_snapshot(owner: User, payload: dict[str, Any]) -> ContextSnapshot:
    activity = (
        Activity.objects.filter(id=payload["activity_id"])
        .filter(Q(owner=owner) | Q(owner__isnull=True))
        .first()
    )
    if activity is None:
        raise ValueError("Activity not found")
    place = None
    if payload.get("geofence_id"):
        place = Geofence.objects.filter(id=payload["geofence_id"], owner=owner).first()
        if place is None:
            raise ValueError("Place not found")
    now = timezone.localtime()
    return ContextSnapshot.objects.create(
        owner=owner,
        activity=activity,
        activity_name=activity.name,
        activity_kind=activity.kind,
        phase=payload.get("phase", ContextSnapshot.Phase.STEADY),
        geofence_reference=place.id if place else None,
        geofence_name=place.name if place else "",
        planned_duration_minutes=payload.get("planned_duration_minutes", 60),
        target_energy=payload.get("target_energy", "0.50"),
        discovery=payload.get("discovery", "0.20"),
        time_bucket=_time_bucket(now.hour),
        is_weekend=now.weekday() >= 5,
    )


def forget_place_learning(owner: User, place: Geofence) -> ContextForgetRecord:
    record = ContextForgetRecord.objects.create(owner=owner, geofence_reference=place.id)
    AuditEvent.objects.create(
        actor=owner,
        action="context.place_learning_forgotten",
        target_type="geofence",
        target_id=str(place.id),
        metadata={"name": place.name},
    )
    return record


def delete_place(owner: User, place: Geofence) -> None:
    AuditEvent.objects.create(
        actor=owner,
        action="context.place_deleted",
        target_type="geofence",
        target_id=str(place.id),
        metadata={"name": place.name, "learning_forget_recorded": True},
    )
    ContextForgetRecord.objects.create(owner=owner, geofence_reference=place.id)
    place.delete()
