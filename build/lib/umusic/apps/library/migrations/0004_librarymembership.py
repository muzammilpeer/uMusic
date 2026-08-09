import uuid

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0003_user_storage_quota_bytes"),
        ("library", "0003_track_energy"),
    ]

    operations = [
        migrations.CreateModel(
            name="LibraryMembership",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid4, editable=False, primary_key=True, serialize=False
                    ),
                ),
                (
                    "state",
                    models.CharField(
                        choices=[("active", "Active"), ("removed", "Removed")],
                        default="active",
                        max_length=16,
                    ),
                ),
                (
                    "source",
                    models.CharField(
                        choices=[
                            ("upload", "Upload"),
                            ("remote_import", "Remote import"),
                            ("backfill", "Backfill"),
                            ("admin", "Administrator"),
                        ],
                        default="upload",
                        max_length=32,
                    ),
                ),
                ("added_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("removed_at", models.DateTimeField(blank=True, null=True)),
                (
                    "owner",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="library_memberships",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "track",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="memberships",
                        to="library.track",
                    ),
                ),
            ],
            options={"ordering": ["-added_at"]},
        ),
        migrations.AddConstraint(
            model_name="librarymembership",
            constraint=models.UniqueConstraint(
                fields=("owner", "track"), name="library_unique_owner_track_membership"
            ),
        ),
        migrations.AddIndex(
            model_name="librarymembership",
            index=models.Index(fields=["owner", "state"], name="library_owner_state_idx"),
        ),
    ]
