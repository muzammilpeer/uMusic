from django.utils import timezone
from rest_framework.test import APIClient, APITestCase

from umusic.apps.accounts.models import User
from umusic.apps.accounts.v2_api import _issue_session
from umusic.apps.library.models import Album, Artist, AudioFile, LibraryMembership, Track
from umusic.apps.library.audio_analysis import analyze_track


class V2LibraryChangesTests(APITestCase):
    def setUp(self) -> None:
        self.owner = User.objects.create_user(username="owner", password="password")
        self.other = User.objects.create_user(username="other", password="password")
        from umusic.apps.accounts.models import Device

        device, _ = Device.issue(owner=self.owner, name="Test")
        session = _issue_session(device)
        self.client = APIClient()
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {session['access_token']}")

    def make_track(self, title: str, owner: User) -> Track:
        artist = Artist.objects.create(
            name=f"{title} Artist", normalized_name=f"{title.lower()}-artist"
        )
        album = Album.objects.create(
            title=f"{title} Album", normalized_title=f"{title.lower()}-album", album_artist=artist
        )
        audio = AudioFile.objects.create(
            checksum=(title.encode().hex() + "0" * 64)[:64],
            storage_backend="local",
            object_key=f"{title}.mp3",
            original_filename=f"{title}.mp3",
            size_bytes=1_000,
            duration_ms=120_000,
            bitrate=256_000,
        )
        track = Track.objects.create(
            title=title, artist=artist, album=album, audio_file=audio, genres=["Test"], year=2001
        )
        LibraryMembership.objects.create(owner=owner, track=track)
        return track

    def test_changes_are_paginated_and_user_isolated(self) -> None:
        first = self.make_track("First", self.owner)
        second = self.make_track("Second", self.owner)
        self.make_track("Private", self.other)

        page1 = self.client.get("/api/v2/library/changes", {"limit": 1})
        self.assertEqual(page1.status_code, 200)
        self.assertTrue(page1.data["has_more"])
        self.assertEqual(len(page1.data["tracks"]), 1)
        page2 = self.client.get(
            "/api/v2/library/changes", {"limit": 1, "cursor": page1.data["next_cursor"]}
        )
        self.assertEqual(page2.status_code, 200)
        returned = {page1.data["tracks"][0]["id"], page2.data["tracks"][0]["id"]}
        self.assertEqual(returned, {str(first.id), str(second.id)})

    def test_completed_cursor_returns_tombstone_on_next_sync(self) -> None:
        track = self.make_track("Removed", self.owner)
        initial = self.client.get("/api/v2/library/changes")
        self.assertFalse(initial.data["has_more"])
        membership = LibraryMembership.objects.get(owner=self.owner, track=track)
        membership.state = LibraryMembership.State.REMOVED
        membership.removed_at = timezone.now()
        membership.save(update_fields=["state", "removed_at", "updated_at"])

        changes = self.client.get(
            "/api/v2/library/changes", {"cursor": initial.data["next_cursor"]}
        )
        self.assertEqual(changes.status_code, 200)
        self.assertEqual(changes.data["tracks"], [])
        self.assertEqual(changes.data["tombstones"][0]["track_id"], str(track.id))

    def test_invalid_cursor_is_controlled(self) -> None:
        response = self.client.get("/api/v2/library/changes", {"cursor": "bad"})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["code"], "invalid_cursor")

    def test_content_classification_is_explicit_confident_and_allowlisted(self) -> None:
        track = self.make_track("Classified", self.owner)
        track.content_classifications = [
            {"category": "quranTranslation", "confidence": 0.92},
            {"category": "inferred_from_language", "confidence": 1},
            {"category": "quran", "confidence": 9},
        ]
        track.save(update_fields=["content_classifications", "updated_at"])
        response = self.client.get("/api/v2/library/changes")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.data["tracks"][0]["content_classifications"],
            [
                {"category": "quranTranslation", "confidence": 0.92},
                {"category": "quran", "confidence": 1},
            ],
        )

    def test_successful_song_features_are_bounded_and_owner_scoped(self) -> None:
        track = self.make_track("Analyzed", self.owner)
        private = self.make_track("PrivateAnalysis", self.other)
        analyze_track(track.id)
        analyze_track(private.id)

        response = self.client.get("/api/v2/library/changes")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["tracks"]), 1)
        features = response.data["tracks"][0]["song_features"]
        self.assertEqual(features["schema_version"], 1)
        self.assertEqual(features["provider"], "deterministic")
        self.assertEqual(features["embedding"]["dimension"], 64)
        self.assertEqual(features["embedding"]["encoding"], "float16_le")
        self.assertLessEqual(len(features["embedding"]["payload"]), 256)
