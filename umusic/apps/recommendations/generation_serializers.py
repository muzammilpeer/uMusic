from rest_framework import serializers

from umusic.apps.recommendations.models import GeneratedPlaylist, GeneratedPlaylistTrack


class GenerationInputSerializer(serializers.Serializer):
    activity_id = serializers.UUIDField()
    geofence_id = serializers.UUIDField(required=False, allow_null=True)
    duration_minutes = serializers.IntegerField(min_value=5, max_value=1440, default=60)
    offline_quota_bytes = serializers.IntegerField(
        min_value=1024 * 1024,
        max_value=100 * 1024 * 1024 * 1024,
        required=False,
    )
    target_energy = serializers.FloatField(min_value=0, max_value=1, default=0.7)
    discovery = serializers.FloatField(min_value=0, max_value=1, default=0.2)
    seed = serializers.IntegerField(min_value=0, max_value=2**63 - 1)


class GeneratedTrackSerializer(serializers.ModelSerializer):
    track_id = serializers.UUIDField(read_only=True)
    title = serializers.CharField(source="track.title")
    artist = serializers.CharField(source="track.artist.name")
    duration_ms = serializers.IntegerField(source="track.audio_file.duration_ms")

    class Meta:
        model = GeneratedPlaylistTrack
        fields = [
            "position",
            "track_id",
            "title",
            "artist",
            "duration_ms",
            "score",
            "target_energy",
            "reasons",
        ]


class GeneratedPlaylistSerializer(serializers.ModelSerializer):
    tracks = GeneratedTrackSerializer(source="items", many=True)

    class Meta:
        model = GeneratedPlaylist
        fields = [
            "id",
            "source_version_id",
            "context_snapshot_id",
            "activity_kind",
            "geofence_reference",
            "requested_duration_minutes",
            "actual_duration_ms",
            "target_energy",
            "discovery",
            "seed",
            "model_version",
            "input_digest",
            "created_at",
            "tracks",
        ]
