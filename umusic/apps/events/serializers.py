from rest_framework import serializers

from umusic.apps.events.models import ListeningEvent


class ListeningEventInputSerializer(serializers.Serializer):
    client_event_id = serializers.UUIDField()
    playback_id = serializers.UUIDField()
    track_id = serializers.UUIDField()
    playback_session_id = serializers.UUIDField(required=False, allow_null=True)
    context_snapshot_id = serializers.UUIDField(required=False, allow_null=True)
    event_type = serializers.ChoiceField(choices=ListeningEvent.Type.values)
    client_timestamp = serializers.DateTimeField()
    position_ms = serializers.IntegerField(required=False, min_value=0, default=0)
    duration_ms = serializers.IntegerField(required=False, min_value=0, default=0)
    listened_ms_delta = serializers.IntegerField(required=False, min_value=0, default=0)
    offline = serializers.BooleanField(required=False, default=False)
    metadata = serializers.JSONField(required=False, default=dict)


class ListeningEventOutputSerializer(serializers.ModelSerializer):
    class Meta:
        model = ListeningEvent
        fields = [
            "id",
            "client_event_id",
            "playback_id",
            "track_id",
            "playback_session_id",
            "context_snapshot_id",
            "event_type",
            "client_timestamp",
            "received_at",
            "position_ms",
            "duration_ms",
            "listened_ms_delta",
            "offline",
            "metadata",
        ]
