from rest_framework import serializers

from umusic.apps.contexts.models import Activity, ContextSnapshot, Geofence


class ActivitySerializer(serializers.ModelSerializer):
    class Meta:
        model = Activity
        fields = ["id", "name", "slug", "kind", "phase_curve", "is_preset"]
        read_only_fields = ["id", "kind", "is_preset"]


class GeofenceSerializer(serializers.ModelSerializer):
    latitude = serializers.DecimalField(max_digits=9, decimal_places=6, min_value=-90, max_value=90)
    longitude = serializers.DecimalField(
        max_digits=9, decimal_places=6, min_value=-180, max_value=180
    )
    radius_m = serializers.IntegerField(min_value=25, max_value=100_000)

    class Meta:
        model = Geofence
        fields = [
            "id",
            "name",
            "latitude",
            "longitude",
            "radius_m",
            "privacy",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]


class ContextSnapshotInputSerializer(serializers.Serializer):
    activity_id = serializers.UUIDField()
    geofence_id = serializers.UUIDField(required=False, allow_null=True)
    phase = serializers.ChoiceField(choices=ContextSnapshot.Phase.values, default="steady")
    planned_duration_minutes = serializers.IntegerField(min_value=1, max_value=1440, default=60)
    target_energy = serializers.DecimalField(
        max_digits=3, decimal_places=2, min_value=0, max_value=1, default="0.50"
    )
    discovery = serializers.DecimalField(
        max_digits=3, decimal_places=2, min_value=0, max_value=1, default="0.20"
    )


class ContextSnapshotSerializer(serializers.ModelSerializer):
    class Meta:
        model = ContextSnapshot
        fields = [
            "id",
            "activity_id",
            "activity_name",
            "activity_kind",
            "phase",
            "geofence_reference",
            "geofence_name",
            "planned_duration_minutes",
            "target_energy",
            "discovery",
            "time_bucket",
            "is_weekend",
            "created_at",
        ]
