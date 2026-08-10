import json
from typing import Any

import redis
from django.conf import settings
from django.contrib import messages
from django.contrib.auth import logout
from django.contrib.auth.decorators import login_required
from django.core.paginator import Paginator
from django.db.models import Q
from django.http import HttpRequest, HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.utils.text import slugify

from umusic.apps.accounts.models import Device, User
from umusic.apps.accounts.privacy import delete_listening_and_learning, export_owner_data
from umusic.apps.contexts.models import Activity, ContextSnapshot, Geofence
from umusic.apps.contexts.serializers import ContextSnapshotInputSerializer, GeofenceSerializer
from umusic.apps.contexts.services import create_snapshot, delete_place, forget_place_learning
from umusic.apps.events.models import ListeningEvent, PlayFact
from umusic.apps.imports.adapters import enabled_adapters
from umusic.apps.imports.models import AdapterJob, TasteCandidate
from umusic.apps.imports.remote_services import create_remote_import
from umusic.apps.library.forms import TrackMetadataForm
from umusic.apps.library.models import Album, Artist, ImportJob
from umusic.apps.library.services import (
    ImportFailure,
    accessible_tracks,
    remove_track_from_library,
    update_track_metadata,
)
from umusic.apps.library.storage import get_media_storage
from umusic.apps.operations.models import OperationalJob
from umusic.apps.operations.tasks import refresh_owner_playlists
from umusic.apps.playback.models import PlaybackSession
from umusic.apps.playlists.models import Playlist
from umusic.apps.recommendations.evaluation import evaluation_rows
from umusic.apps.recommendations.generation_serializers import GenerationInputSerializer
from umusic.apps.recommendations.generation_views import generate_from_data
from umusic.apps.recommendations.generator import regenerate_playlist, replace_track
from umusic.apps.recommendations.models import Affinity, GeneratedPlaylist, LearningRun
from umusic.apps.recommendations.services import rebuild_affinities, reset_learning


@login_required
def index(request: HttpRequest) -> HttpResponse:
    query = request.GET.get("q", "").strip()
    user = request.user
    assert isinstance(user, User)
    tracks = accessible_tracks(user).select_related("artist", "album", "audio_file")
    if query:
        tracks = tracks.filter(
            Q(title__icontains=query)
            | Q(artist__name__icontains=query)
            | Q(album__title__icontains=query)
        )
    page = Paginator(tracks, 50).get_page(request.GET.get("page"))
    playlists = Playlist.objects.filter(owner=user)
    return render(
        request, "library/index.html", {"page": page, "query": query, "playlists": playlists}
    )


@login_required
def track_detail(request: HttpRequest, track_id: Any) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    track = get_object_or_404(
        accessible_tracks(user).select_related("artist", "album", "audio_file"),
        id=track_id,
    )
    if request.method == "POST" and request.POST.get("action") == "delete":
        if request.POST.get("confirmation") != "DELETE":
            messages.error(request, "Type DELETE to confirm removal from your library.")
            return redirect("library:track-detail", track_id=track.id)
        remove_track_from_library(track, user)
        messages.success(request, "Track removed from your private library.")
        return redirect("library:index")
    initial = {
        "title": track.title,
        "artist": track.artist.name,
        "album": track.album.title if track.album else "",
        "year": track.year,
        "track_number": track.track_number,
        "disc_number": track.disc_number,
        "genres": ", ".join(track.genres),
        "content_categories": [
            item.get("category")
            for item in track.content_classifications
            if isinstance(item, dict)
        ],
        "content_confidence": next(
            (
                item.get("confidence")
                for item in track.content_classifications
                if isinstance(item, dict)
            ),
            1,
        ),
    }
    form = TrackMetadataForm(request.POST or None, initial=initial)
    if request.method == "POST" and form.is_valid():
        try:
            if track.memberships.filter(state="active").exclude(owner=user).exists():
                raise ImportFailure(
                    "SHARED_METADATA",
                    "This catalog file is shared by another library and cannot be edited here.",
                )
            update_track_metadata(track, user, form.cleaned_data)
            confidence = float(form.cleaned_data.get("content_confidence") or 0)
            track.content_classifications = [
                {"category": category, "confidence": confidence}
                for category in form.cleaned_data.get("content_categories", [])
            ]
            track.save(update_fields=["content_classifications", "updated_at"])
            messages.success(request, "MP3 tags, library metadata, checksum, and filename updated.")
            return redirect("library:track-detail", track_id=track.id)
        except ImportFailure as error:
            messages.error(request, error.message)
        except Exception:
            messages.error(request, "The MP3 metadata could not be updated safely.")
    return render(request, "library/track_detail.html", {"track": track, "form": form})


@login_required
def artist_detail(request: HttpRequest, artist_id: Any) -> HttpResponse:
    tracks = accessible_tracks(request.user).filter(artist_id=artist_id).select_related(
        "artist", "album", "audio_file"
    )
    artist = get_object_or_404(Artist, id=artist_id, tracks__in=tracks)
    return render(request, "library/artist_detail.html", {"artist": artist, "tracks": tracks})


@login_required
def album_detail(request: HttpRequest, album_id: Any) -> HttpResponse:
    tracks = accessible_tracks(request.user).filter(album_id=album_id).select_related(
        "artist", "album", "audio_file"
    )
    album = get_object_or_404(
        Album.objects.select_related("album_artist").filter(tracks__in=tracks).distinct(),
        id=album_id,
    )
    return render(request, "library/album_detail.html", {"album": album, "tracks": tracks})


@login_required
def imports(request: HttpRequest) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    jobs = ImportJob.objects.filter(owner=user).select_related("track", "track__artist")[:100]
    return render(request, "library/imports.html", {"jobs": jobs})


@login_required
def import_detail(request: HttpRequest, job_id: Any) -> HttpResponse:
    job = get_object_or_404(
        ImportJob.objects.select_related("track", "track__artist"),
        id=job_id,
        owner=request.user,
    )
    return render(request, "library/import_detail.html", {"job": job})


@login_required
def event_history(request: HttpRequest) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    events = ListeningEvent.objects.filter(owner=user).select_related(
        "track", "track__artist", "context_snapshot"
    )
    activity = request.GET.get("activity", "")
    place = request.GET.get("place", "")
    if activity:
        events = events.filter(context_snapshot__activity_kind=activity)
    if place:
        events = events.filter(context_snapshot__geofence_reference=place)
    facts = PlayFact.objects.filter(
        owner=user, playback_id__in=events.values_list("playback_id", flat=True)
    ).select_related("track", "track__artist")[:100]
    return render(
        request,
        "library/events.html",
        {
            "events": events[:200],
            "facts": facts,
            "activity_choices": Activity.Kind.choices,
            "places": Geofence.objects.filter(owner=user),
            "selected_activity": activity,
            "selected_place": place,
        },
    )


@login_required
def context_setup(request: HttpRequest) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    created = None
    if request.method == "POST":
        if request.POST.get("action") == "custom_activity":
            name = request.POST.get("name", "").strip()
            if name:
                Activity.objects.create(
                    owner=user,
                    name=name,
                    slug=slugify(name),
                    kind=Activity.Kind.CUSTOM,
                    phase_curve=[],
                )
                messages.success(request, "Custom activity created.")
                return redirect("library:context-setup")
        else:
            serializer = ContextSnapshotInputSerializer(data=request.POST)
            if serializer.is_valid():
                created = create_snapshot(user, serializer.validated_data)
                messages.success(request, "Listening context is active in this browser.")
            else:
                messages.error(request, str(serializer.errors))
    return render(
        request,
        "library/context_setup.html",
        {
            "activities": Activity.objects.filter(Q(owner=user) | Q(owner__isnull=True)),
            "places": Geofence.objects.filter(owner=user),
            "phases": ContextSnapshot.Phase.choices,
            "created": created,
        },
    )


@login_required
def places(request: HttpRequest) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    if request.method == "POST":
        action = request.POST.get("action", "create")
        place_id = request.POST.get("place_id")
        place = Geofence.objects.filter(id=place_id, owner=user).first() if place_id else None
        if action == "delete" and place:
            delete_place(user, place)
            messages.success(request, "Place coordinates deleted; anonymous history remains.")
        elif action == "forget" and place:
            forget_place_learning(user, place)
            messages.success(request, "Learned associations for this place will be ignored.")
        elif action == "create":
            serializer = GeofenceSerializer(data=request.POST)
            if serializer.is_valid():
                serializer.save(owner=user)
                messages.success(request, "Named place created.")
            else:
                messages.error(request, str(serializer.errors))
        return redirect("library:places")
    return render(request, "library/places.html", {"places": Geofence.objects.filter(owner=user)})


@login_required
def learning(request: HttpRequest) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    if request.method == "POST":
        if request.POST.get("action") == "reset":
            reset_learning(user)
            messages.success(
                request, "Derived learning was reset; raw listening history is unchanged."
            )
        else:
            run = rebuild_affinities(user)
            messages.success(request, f"Rebuilt {run.affinity_count} explainable affinities.")
        return redirect("library:learning")
    affinities = Affinity.objects.filter(owner=user).select_related("configuration")[:300]
    latest_run = LearningRun.objects.filter(owner=user).select_related("configuration").first()
    return render(
        request, "library/learning.html", {"affinities": affinities, "latest_run": latest_run}
    )


@login_required
def generated_playlists(request: HttpRequest) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    if request.method == "POST":
        serializer = GenerationInputSerializer(data=request.POST)
        if serializer.is_valid():
            try:
                playlist = generate_from_data(user, serializer.validated_data)
                return redirect("library:generated-detail", playlist_id=playlist.id)
            except ValueError as error:
                messages.error(request, str(error))
        else:
            messages.error(request, str(serializer.errors))
    return render(
        request,
        "library/generated_playlists.html",
        {
            "activities": Activity.objects.filter(Q(owner=user) | Q(owner__isnull=True)),
            "places": Geofence.objects.filter(owner=user),
            "playlists": GeneratedPlaylist.objects.filter(owner=user)[:50],
        },
    )


@login_required
def generated_detail(request: HttpRequest, playlist_id: Any) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    playlist = get_object_or_404(GeneratedPlaylist, id=playlist_id, owner=user)
    if request.method == "POST":
        try:
            if request.POST.get("action") == "replace":
                new_version = replace_track(user, playlist, int(request.POST.get("position", "-1")))
            else:
                seed_text = request.POST.get("seed", "")
                new_version = regenerate_playlist(
                    user, playlist, int(seed_text) if seed_text else None
                )
            return redirect("library:generated-detail", playlist_id=new_version.id)
        except ValueError as error:
            messages.error(request, str(error))
    items = playlist.items.select_related("track", "track__artist", "track__audio_file")
    return render(request, "library/generated_detail.html", {"playlist": playlist, "items": items})


@login_required
def adapter_inbox(request: HttpRequest) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    if request.method == "POST":
        try:
            job = create_remote_import(
                user,
                request.POST.get("urls", ""),
                request.POST.get("attested") == "on",
            )
            messages.success(request, f"Queued {job.request['item_count']} remote URL(s).")
        except (ValueError, PermissionError) as error:
            messages.error(request, str(error))
        return redirect("library:adapter-inbox")
    return render(
        request,
        "library/adapter_inbox.html",
        {
            "enabled_adapters": enabled_adapters(),
            "jobs": AdapterJob.objects.filter(owner=user)[:50],
            "candidates": TasteCandidate.objects.filter(job__owner=user).select_related(
                "matched_track"
            )[:200],
        },
    )


@login_required
def operations_dashboard(request: HttpRequest) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    if request.method == "POST":
        job_id = request.POST.get("job_id")
        failed = (
            OperationalJob.objects.filter(id=job_id, owner=user, status="failed").first()
            if job_id
            else None
        )
        key = (
            failed.idempotency_key
            if failed
            else f"manual-refresh:{user.id}:{timezone.now().isoformat()}"
        )
        job = refresh_owner_playlists(user, key)
        messages.success(request, f"Refresh finished: {job.status}.")
        return redirect("library:operations")
    health = get_media_storage().health()
    client = redis.Redis.from_url(settings.REDIS_URL)
    try:
        queue_depth = client.llen("celery")
    finally:
        client.close()  # type: ignore[no-untyped-call]
    return render(
        request,
        "library/operations.html",
        {
            "storage": health,
            "queue_depth": queue_depth,
            "failed_imports": ImportJob.objects.filter(status="failed").count(),
            "adapter_failures": AdapterJob.objects.filter(owner=user, status="failed").count(),
            "active_sessions": PlaybackSession.objects.filter(owner=user, status="active").count(),
            "latest_learning": LearningRun.objects.filter(owner=user).first(),
            "jobs": OperationalJob.objects.filter(owner=user)[:50],
            "wanted": TasteCandidate.objects.filter(job__owner=user, state="unmatched")[:100],
        },
    )


@login_required
def devices(request: HttpRequest) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    if request.method == "POST":
        device_id = request.POST.get("device_id")
        device = Device.objects.filter(id=device_id, owner=user).first() if device_id else None
        if device and device.revoked_at is None:
            device.revoked_at = timezone.now()
            device.save(update_fields=["revoked_at"])
            messages.success(request, f"Revoked {device.name}.")
        return redirect("library:devices")
    return render(request, "library/devices.html", {"devices": Device.objects.filter(owner=user)})


@login_required
def evaluation(request: HttpRequest) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    rows = evaluation_rows(user)
    has_evidence = any(row["plays"] != 0 for row in rows)
    return render(
        request,
        "library/evaluation.html",
        {"rows": rows, "has_evidence": has_evidence},
    )


@login_required
def privacy(request: HttpRequest) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    if request.method == "POST":
        action = request.POST.get("action")
        confirmation = request.POST.get("confirmation", "")
        if action == "delete_history" and confirmation == "DELETE HISTORY":
            deleted = delete_listening_and_learning(user)
            messages.success(request, f"Listening and learned data deleted: {deleted}.")
            return redirect("library:privacy")
        if action == "delete_account" and confirmation == "DELETE ACCOUNT":
            logout(request)
            user.delete()
            return redirect("login")
        messages.error(request, "The confirmation phrase did not match.")
    return render(request, "library/privacy.html")


@login_required
def privacy_export(request: HttpRequest) -> HttpResponse:
    user = request.user
    assert isinstance(user, User)
    response = HttpResponse(
        json.dumps(export_owner_data(user), indent=2, default=str),
        content_type="application/json",
    )
    response["Content-Disposition"] = 'attachment; filename="umusic-data-export.json"'
    response["Cache-Control"] = "private, no-store"
    return response
