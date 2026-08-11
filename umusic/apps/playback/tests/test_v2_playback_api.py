import hashlib
import tempfile
from pathlib import Path

from django.test import override_settings
from django.urls import reverse
from rest_framework.test import APIClient, APITestCase

from umusic.apps.accounts.models import Device, User
from umusic.apps.accounts.v2_api import _issue_session
from umusic.apps.library.models import Artist, AudioFile, LibraryMembership, Track
from umusic.apps.library.storage import audio_object_key, get_media_storage


class V2PlaybackTicketsTests(APITestCase):
    def setUp(self) -> None:
        self.media_directory = tempfile.TemporaryDirectory()
        self.settings_override = override_settings(MEDIA_ROOT=Path(self.media_directory.name))
        self.settings_override.enable()
        self.addCleanup(self.settings_override.disable)
        self.addCleanup(self.media_directory.cleanup)
        self.user = User.objects.create_user(username="listener", password="password")
        device, _ = Device.issue(owner=self.user, name="Test")
        session = _issue_session(device)
        self.client = APIClient()
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {session['access_token']}")
        content = b"ID3" + b"audio" * 30
        checksum = hashlib.sha256(content).hexdigest()
        key = audio_object_key(checksum)
        storage = get_media_storage()
        source = Path(self.media_directory.name) / "source.mp3"
        source.write_bytes(content)
        storage.publish(source, key, checksum)
        artist = Artist.objects.create(name="Artist", normalized_name="artist")
        audio = AudioFile.objects.create(
            checksum=checksum,
            storage_backend="local",
            object_key=key,
            original_filename="track.mp3",
            size_bytes=len(content),
            duration_ms=120_000,
        )
        self.track = Track.objects.create(title="Track", artist=artist, audio_file=audio)
        LibraryMembership.objects.create(owner=self.user, track=self.track)
        self.content = content

    def test_ticket_streams_without_bearer_and_supports_range(self) -> None:
        response = self.client.post(
            reverse("api-v2-playback-tickets"), {"track_ids": [str(self.track.id)]}, format="json"
        )
        self.assertEqual(response.status_code, 200)
        ticket_url = response.data["tickets"][0]["url"]
        anonymous = APIClient()
        streamed = anonymous.get(ticket_url, HTTP_RANGE="bytes=0-2")
        self.assertEqual(streamed.status_code, 206)
        self.assertEqual(b"".join(streamed.streaming_content), b"ID3")

    def test_ticket_accepts_uppercase_uuid_from_swift_clients(self) -> None:
        response = self.client.post(
            reverse("api-v2-playback-tickets"),
            {"track_ids": [str(self.track.id).upper()]},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["tickets"][0]["track_id"], str(self.track.id))

    def test_ticket_is_device_bound_and_rejects_tampering(self) -> None:
        response = self.client.post(
            reverse("api-v2-playback-tickets"), {"track_ids": [str(self.track.id)]}, format="json"
        )
        ticket_url = response.data["tickets"][0]["url"]
        replacement = "a" if ticket_url[-1] != "a" else "b"
        denied = APIClient().get(f"{ticket_url[:-1]}{replacement}")
        self.assertEqual(denied.status_code, 401)
