import base64
import hashlib
import tempfile
import uuid
from pathlib import Path
from typing import cast

from django.core import signing
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.test.utils import override_settings
from django.urls import reverse
from rest_framework.test import APIClient

from umusic.apps.accounts.models import Device, User
from umusic.apps.accounts.privacy import export_owner_data
from umusic.apps.library.models import Artist, AudioFile, LibraryMembership, Track
from umusic.apps.library.services import (
    ImportFailure,
    add_library_membership,
    process_import,
    quarantine_upload,
)
from umusic.apps.library.tests.conftest import SILENT_MP3_BASE64


class MultiUserIsolationTests(TestCase):
    def setUp(self) -> None:
        self.alice = User.objects.create_user(username="alice", password="test-password-123")
        self.bob = User.objects.create_user(username="bob", password="test-password-123")
        self.alice_device, self.alice_token = Device.issue(owner=self.alice, name="Alice iPhone")
        self.bob_device, _ = Device.issue(owner=self.bob, name="Bob iPhone")
        artist = Artist.objects.create(name="Private Artist", normalized_name="private artist")
        self.alice_track = self._track(artist, "Alice Song")
        self.bob_track = self._track(artist, "Bob Song")
        LibraryMembership.objects.create(owner=self.alice, track=self.alice_track)
        LibraryMembership.objects.create(owner=self.bob, track=self.bob_track)
        self.api_client = APIClient()
        self.api_client.force_authenticate(user=self.alice, token=self.alice_device)

    def _track(self, artist: Artist, title: str) -> Track:
        value = title.encode()
        audio = AudioFile.objects.create(
            checksum=hashlib.sha256(value).hexdigest(),
            storage_backend="local",
            object_key=f"audio/{uuid.uuid4()}.mp3",
            original_filename=f"{title}.mp3",
            size_bytes=100,
            duration_ms=180_000,
        )
        return Track.objects.create(title=title, artist=artist, audio_file=audio)

    def test_track_catalog_detail_and_stream_are_private(self) -> None:
        response = self.api_client.get(reverse("api-track-list"))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            [item["id"] for item in response.json()["results"]],
            [str(self.alice_track.id)],
        )
        self.assertEqual(
            self.api_client.get(reverse("api-track-detail", args=[self.bob_track.id])).status_code,
            404,
        )
        self.api_client.force_login(self.alice)
        self.assertEqual(
            self.api_client.get(reverse("api-track-stream", args=[self.bob_track.id])).status_code,
            404,
        )

    def test_private_track_cannot_enter_playback_events_or_playlist(self) -> None:
        playback = self.api_client.post(
            reverse("api-playback-sessions"),
            {"track_ids": [str(self.bob_track.id)]},
            format="json",
        )
        self.assertEqual(playback.status_code, 400)
        event = self.api_client.post(
            reverse("api-event-batch"),
            {
                "events": [
                    {
                        "client_event_id": str(uuid.uuid4()),
                        "playback_id": str(uuid.uuid4()),
                        "track_id": str(self.bob_track.id),
                        "event_type": "started",
                        "client_timestamp": "2026-08-03T00:00:00Z",
                        "position_ms": 0,
                        "duration_ms": 180000,
                        "offline": False,
                    }
                ]
            },
            format="json",
        )
        self.assertEqual(event.status_code, 400)

    def test_signed_download_is_bound_to_device_owner_membership(self) -> None:
        token = signing.dumps(
            {"track_id": str(self.bob_track.id), "device_id": str(self.alice_device.id)},
            salt="umusic-sync-download",
            compress=True,
        )
        response = self.api_client.get(reverse("sync-download", args=[token]))
        self.assertEqual(response.status_code, 401)

    def test_removal_does_not_affect_another_users_membership(self) -> None:
        LibraryMembership.objects.create(owner=self.bob, track=self.alice_track)
        response = self.api_client.delete(reverse("api-track-detail", args=[self.alice_track.id]))
        self.assertEqual(response.status_code, 204)
        self.assertFalse(
            LibraryMembership.objects.filter(
                owner=self.alice,
                track=self.alice_track,
                state=LibraryMembership.State.ACTIVE,
            ).exists()
        )
        self.assertTrue(
            LibraryMembership.objects.filter(
                owner=self.bob,
                track=self.alice_track,
                state=LibraryMembership.State.ACTIVE,
            ).exists()
        )
        self.alice_track.refresh_from_db()
        self.assertTrue(self.alice_track.is_active)

    def test_quota_and_disabled_device_authentication(self) -> None:
        self.alice.storage_quota_bytes = 100
        self.alice.save(update_fields=["storage_quota_bytes"])
        with self.assertRaises(ImportFailure):
            add_library_membership(self.alice, self.bob_track)

        self.alice.is_active = False
        self.alice.save(update_fields=["is_active"])
        token_client = APIClient()
        token_client.credentials(HTTP_AUTHORIZATION=f"Bearer {self.alice_token}")
        self.assertIn(token_client.get(reverse("api-me")).status_code, {401, 403})

    def test_duplicate_mp3_is_shared_physically_but_memberships_stay_private(self) -> None:
        content = base64.b64decode("".join(SILENT_MP3_BASE64.split()))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with override_settings(
                MEDIA_ROOT=root / "media",
                UMUSIC_QUARANTINE_ROOT=root / "quarantine",
            ):
                for owner in (self.alice, self.bob):
                    upload = SimpleUploadedFile("same.mp3", content, content_type="audio/mpeg")
                    job = process_import(quarantine_upload(upload, owner))
                    self.assertIn(job.status, {"completed", "duplicate"})
                imported = Track.objects.exclude(id__in=[self.alice_track.id, self.bob_track.id])
                self.assertEqual(imported.count(), 1)
                track = imported.get()
                self.assertEqual(
                    LibraryMembership.objects.filter(
                        track=track, state=LibraryMembership.State.ACTIVE
                    ).count(),
                    2,
                )

    def test_privacy_export_and_account_deletion_do_not_cross_users(self) -> None:
        LibraryMembership.objects.create(owner=self.bob, track=self.alice_track)
        exported = export_owner_data(self.alice)
        memberships = cast(list[dict[str, object]], exported["library_memberships"])
        exported_track_ids = {
            str(item["track_id"]) for item in memberships
        }
        self.assertEqual(exported_track_ids, {str(self.alice_track.id)})
        self.alice.delete()
        self.assertTrue(
            LibraryMembership.objects.filter(
                owner=self.bob,
                track=self.alice_track,
                state=LibraryMembership.State.ACTIVE,
            ).exists()
        )
        self.assertTrue(Track.objects.filter(id=self.alice_track.id).exists())
