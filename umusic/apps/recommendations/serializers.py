from rest_framework import serializers

from umusic.apps.recommendations.models import Affinity, LearningRun


class AffinitySerializer(serializers.ModelSerializer):
    algorithm_version = serializers.CharField(source="configuration.version")

    class Meta:
        model = Affinity
        fields = [
            "id",
            "target_type",
            "target_id",
            "target_label",
            "context_type",
            "context_key",
            "score",
            "confidence",
            "positive_evidence",
            "negative_evidence",
            "sample_count",
            "explicit_preference",
            "evidence",
            "last_observation",
            "algorithm_version",
        ]


class LearningRunSerializer(serializers.ModelSerializer):
    algorithm_version = serializers.CharField(source="configuration.version")

    class Meta:
        model = LearningRun
        fields = [
            "id",
            "status",
            "affinity_count",
            "evidence_digest",
            "error",
            "started_at",
            "completed_at",
            "algorithm_version",
        ]
