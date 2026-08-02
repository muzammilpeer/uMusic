from rest_framework import serializers

from umusic.apps.library.models import ImportJob


class UploadSerializer(serializers.Serializer[dict[str, object]]):
    file = serializers.FileField(required=True, allow_empty_file=False)


class ImportJobSerializer(serializers.ModelSerializer[ImportJob]):
    track_id = serializers.UUIDField(read_only=True)

    class Meta:
        model = ImportJob
        fields = [
            "id",
            "status",
            "source_filename",
            "size_bytes",
            "checksum",
            "track_id",
            "error_code",
            "error_message",
            "created_at",
            "started_at",
            "completed_at",
        ]
        read_only_fields = fields
