import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("library", "0005_track_content_classifications")]
    operations = [
        migrations.CreateModel(
            name="TrackAnalysis",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("source_checksum", models.CharField(max_length=64)),
                ("provider", models.CharField(max_length=64)),
                ("model_version", models.CharField(max_length=128)),
                ("feature_schema_version", models.PositiveSmallIntegerField(default=1)),
                ("status", models.CharField(choices=[("pending", "Pending"), ("running", "Running"), ("succeeded", "Succeeded"), ("retryable_failure", "Retryable failure"), ("permanent_failure", "Permanent failure"), ("superseded", "Superseded"), ("cancelled", "Cancelled")], default="pending", max_length=32)),
                ("attempt_count", models.PositiveIntegerField(default=0)),
                ("scalar_features", models.JSONField(blank=True, default=dict)),
                ("embedding_dimension", models.PositiveSmallIntegerField(default=0)),
                ("embedding_encoding", models.CharField(default="float16_le", max_length=32)),
                ("embedding", models.BinaryField(blank=True, default=bytes)),
                ("error_code", models.CharField(blank=True, max_length=64)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("completed_at", models.DateTimeField(blank=True, null=True)),
                ("track", models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name="analysis", to="library.track")),
            ],
        ),
        migrations.AddIndex(model_name="trackanalysis", index=models.Index(fields=["status", "updated_at"], name="library_analysis_status_idx")),
    ]
