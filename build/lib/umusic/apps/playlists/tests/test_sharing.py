from datetime import timedelta

import pytest
from django.test import Client
from django.urls import reverse
from django.utils import timezone

from umusic.apps.accounts.models import User
from umusic.apps.library.models import Artist, AudioFile, LibraryMembership, Track
from umusic.apps.playlists.models import Playlist, PlaylistAccess, PlaylistInvitation, PlaylistTrack


def make_track(owner: User, suffix: str = "one") -> Track:
    artist, _ = Artist.objects.get_or_create(
        normalized_name=f"artist-{suffix}", defaults={"name": f"Artist {suffix}"}
    )
    audio = AudioFile.objects.create(
        checksum=(suffix * 64)[:64],
        storage_backend="local",
        object_key=f"music/{suffix}.mp3",
        original_filename=f"{suffix}.mp3",
        size_bytes=100,
        duration_ms=30_000,
    )
    track = Track.objects.create(title=f"Song {suffix}", artist=artist, audio_file=audio)
    LibraryMembership.objects.create(owner=owner, track=track)
    return track


@pytest.fixture
def shared() -> tuple[User, User, User, User, Playlist, Track]:
    owner = User.objects.create_user(username="owner", password="password")
    editor = User.objects.create_user(username="editor", password="password")
    viewer = User.objects.create_user(username="viewer", password="password")
    stranger = User.objects.create_user(username="stranger", password="password")
    track = make_track(owner)
    playlist = Playlist.objects.create(owner=owner, name="Shared ride")
    PlaylistTrack.objects.create(playlist=playlist, track=track, position=0)
    PlaylistAccess.objects.create(
        playlist=playlist, user=editor, role=PlaylistAccess.Role.EDITOR, granted_by=owner
    )
    PlaylistAccess.objects.create(
        playlist=playlist, user=viewer, role=PlaylistAccess.Role.VIEWER, granted_by=owner
    )
    return owner, editor, viewer, stranger, playlist, track


@pytest.mark.django_db
def test_roles_visibility_and_mutation(client: Client, shared: tuple) -> None:
    owner, editor, viewer, stranger, playlist, track = shared
    url = reverse("api-playlist", args=[playlist.id])
    client.force_login(editor)
    assert client.get(url).json()["role"] == "editor"
    response = client.patch(
        url,
        data={"revision": playlist.revision, "track_ids": [str(track.id)]},
        content_type="application/json",
    )
    assert response.status_code == 200
    assert response.json()["revision"] == 2
    assert client.patch(
        url,
        data={"revision": 1, "track_ids": []},
        content_type="application/json",
    ).status_code == 409
    client.force_login(viewer)
    assert client.patch(
        url, data={"revision": 2}, content_type="application/json"
    ).status_code == 403
    assert client.delete(url).status_code == 403
    client.force_login(stranger)
    assert client.get(url).status_code == 404


@pytest.mark.django_db
def test_invitation_is_targeted_single_use_and_expires(client: Client, shared: tuple) -> None:
    owner, _editor, _viewer, stranger, playlist, _track = shared
    client.force_login(owner)
    created = client.post(
        reverse("api-playlist-invite", args=[playlist.id]),
        data={"identifier": stranger.username, "role": "viewer"},
        content_type="application/json",
    )
    assert created.status_code == 201
    invitation_id = created.json()["id"]
    client.force_login(stranger)
    response_url = reverse("api-playlist-invitation-respond", args=[invitation_id])
    assert client.post(
        response_url, data={"action": "accept"}, content_type="application/json"
    ).status_code == 204
    assert client.post(
        response_url, data={"action": "accept"}, content_type="application/json"
    ).status_code == 409
    invitation, _ = PlaylistInvitation.issue(
        playlist=playlist,
        invited_user=stranger,
        invited_by=owner,
        role=PlaylistAccess.Role.VIEWER,
        expires_at=timezone.now() - timedelta(seconds=1),
    )
    assert client.post(
        reverse("api-playlist-invitation-respond", args=[invitation.id]),
        data={"action": "accept"},
        content_type="application/json",
    ).status_code == 409


@pytest.mark.django_db
def test_shared_track_can_play_save_and_revocation_blocks_access(
    client: Client, shared: tuple
) -> None:
    owner, _editor, viewer, _stranger, playlist, track = shared
    client.force_login(viewer)
    detail_url = reverse("api-track-detail", args=[track.id])
    assert client.get(detail_url).status_code == 200
    save_url = reverse("api-playlist-track-save", args=[playlist.id, track.id])
    assert client.post(save_url).status_code == 204
    assert LibraryMembership.objects.filter(owner=viewer, track=track).count() == 1
    client.force_login(owner)
    assert client.delete(
        reverse("api-playlist-member", args=[playlist.id, viewer.id])
    ).status_code == 204
    client.force_login(viewer)
    assert client.get(reverse("api-playlist", args=[playlist.id])).status_code == 404
    # An independently saved item survives revocation and remains playable.
    assert client.get(detail_url).status_code == 200


@pytest.mark.django_db
def test_ownership_transfer_reverses_roles(client: Client, shared: tuple) -> None:
    owner, editor, _viewer, _stranger, playlist, _track = shared
    client.force_login(owner)
    response = client.post(
        reverse("api-playlist-transfer", args=[playlist.id]),
        data={"user_id": str(editor.id)},
        content_type="application/json",
    )
    assert response.status_code == 200
    playlist.refresh_from_db()
    assert playlist.owner == editor
    assert PlaylistAccess.objects.filter(
        playlist=playlist,
        user=owner,
        role=PlaylistAccess.Role.EDITOR,
        state=PlaylistAccess.State.ACTIVE,
    ).exists()
