import uuid

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0003_user_storage_quota_bytes"),
        ("playlists", "0001_initial"),
    ]

    operations = [
        migrations.AddField(
            model_name="playlist",
            name="revision",
            field=models.PositiveBigIntegerField(default=1),
        ),
        migrations.CreateModel(
            name="PlaylistAccess",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid4, editable=False, primary_key=True, serialize=False
                    ),
                ),
                (
                    "role",
                    models.CharField(
                        choices=[("editor", "Editor"), ("viewer", "Viewer")], max_length=16
                    ),
                ),
                (
                    "state",
                    models.CharField(
                        choices=[
                            ("active", "Active"),
                            ("revoked", "Revoked"),
                            ("left", "Left"),
                        ],
                        default="active",
                        max_length=16,
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "granted_by",
                    models.ForeignKey(
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="playlist_access_granted",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "playlist",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="access_grants",
                        to="playlists.playlist",
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="playlist_access",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
        ),
        migrations.CreateModel(
            name="PlaylistInvitation",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid4, editable=False, primary_key=True, serialize=False
                    ),
                ),
                (
                    "role",
                    models.CharField(
                        choices=[("editor", "Editor"), ("viewer", "Viewer")], max_length=16
                    ),
                ),
                ("token_prefix", models.CharField(max_length=12, unique=True)),
                ("token_hash", models.CharField(max_length=64)),
                (
                    "state",
                    models.CharField(
                        choices=[
                            ("pending", "Pending"),
                            ("accepted", "Accepted"),
                            ("declined", "Declined"),
                            ("revoked", "Revoked"),
                        ],
                        default="pending",
                        max_length=16,
                    ),
                ),
                ("expires_at", models.DateTimeField()),
                ("responded_at", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "invited_by",
                    models.ForeignKey(
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="playlist_invitations_sent",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "invited_user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="playlist_invitations",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "playlist",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="invitations",
                        to="playlists.playlist",
                    ),
                ),
            ],
            options={"ordering": ["-created_at"]},
        ),
        migrations.AddConstraint(
            model_name="playlistaccess",
            constraint=models.UniqueConstraint(
                fields=("playlist", "user"), name="unique_playlist_user_access"
            ),
        ),
        migrations.AddIndex(
            model_name="playlistaccess",
            index=models.Index(fields=["user", "state"], name="playlist_user_state_idx"),
        ),
        migrations.AddIndex(
            model_name="playlistinvitation",
            index=models.Index(
                fields=["invited_user", "state"], name="playlist_invitee_state_idx"
            ),
        ),
    ]
