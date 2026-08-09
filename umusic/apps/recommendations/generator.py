import hashlib
import json
import random
from dataclasses import dataclass
from decimal import Decimal
from typing import Any

from django.db import transaction

from umusic.apps.accounts.models import User
from umusic.apps.contexts.models import ContextSnapshot
from umusic.apps.events.models import ListeningEvent
from umusic.apps.library.models import Track
from umusic.apps.library.services import accessible_tracks
from umusic.apps.recommendations.models import (
    Affinity,
    GeneratedPlaylist,
    GeneratedPlaylistTrack,
)

GENERATOR_VERSION = "generator-v1"


@dataclass(frozen=True)
class Candidate:
    track: Track
    base_score: float
    familiarity: float
    reasons: list[dict[str, Any]]


def _affinity_map(owner: User) -> dict[tuple[str, str, str, str], Affinity]:
    return {
        (item.target_type, item.target_id, item.context_type, item.context_key): item
        for item in Affinity.objects.filter(owner=owner).select_related("configuration")
    }


def _reason(code: str, label: str, contribution: float) -> dict[str, Any]:
    return {"code": code, "label": label, "contribution": round(contribution, 5)}


def _energy_target(activity: str, requested: float, progress: float, position: int) -> float:
    if activity in {"focus", "relax"}:
        factor = 0.55 if activity == "focus" else 0.40
    elif progress < 0.15:
        factor = 0.72 if activity in {"cycling", "running", "gym"} else 0.85
    elif progress > 0.85:
        factor = 0.65
    elif activity == "gym" and position % 4 == 3:
        factor = 0.65
    else:
        factor = 1.0
    return min(1.0, max(0.0, requested * factor))


def _candidates(
    owner: User,
    activity: str,
    place: str,
    discovery: float,
    seed: int,
) -> list[Candidate]:
    affinities = _affinity_map(owner)
    recent = set(
        ListeningEvent.objects.filter(owner=owner)
        .order_by("-client_timestamp")
        .values_list("track_id", flat=True)[:20]
    )
    rng = random.Random(seed)
    result = []
    tracks = accessible_tracks(owner).select_related("artist", "album", "audio_file")
    for track in sorted(tracks, key=lambda item: str(item.id)):
        global_track = affinities.get(("track", str(track.id), "global", ""))
        if global_track and global_track.explicit_preference < 0:
            continue
        reasons = []
        score = 0.0
        familiarity = float(global_track.confidence) if global_track else 0.0
        if global_track:
            contribution = float(global_track.score) * float(global_track.confidence) * 0.35
            score += contribution
            reasons.append(_reason("GLOBAL_TASTE", "Matches your overall listening", contribution))
        activity_affinity = affinities.get(("track", str(track.id), "activity", activity))
        if activity_affinity:
            contribution = (
                float(activity_affinity.score) * float(activity_affinity.confidence) * 0.25
            )
            score += contribution
            reasons.append(_reason("ACTIVITY_TASTE", f"Learned for {activity}", contribution))
        if place:
            place_affinity = affinities.get(("track", str(track.id), "place", place))
            if place_affinity:
                contribution = float(place_affinity.score) * float(place_affinity.confidence) * 0.10
                score += contribution
                reasons.append(_reason("PLACE_TASTE", "Learned for this place", contribution))
        artist_affinity = affinities.get(("artist", str(track.artist_id), "global", ""))
        if artist_affinity:
            contribution = float(artist_affinity.score) * float(artist_affinity.confidence) * 0.10
            score += contribution
            reasons.append(_reason("ARTIST_TASTE", "You tend to enjoy this artist", contribution))
        discovery_bonus = (1.0 - familiarity) * discovery * 0.20
        familiarity_bonus = familiarity * (1.0 - discovery) * 0.12
        score += discovery_bonus + familiarity_bonus
        if discovery_bonus > familiarity_bonus:
            reasons.append(
                _reason("DISCOVERY", "Adds controlled catalog discovery", discovery_bonus)
            )
        elif familiarity_bonus:
            reasons.append(
                _reason("FAMILIAR", "Uses familiar listening evidence", familiarity_bonus)
            )
        if track.id in recent:
            score -= 0.35
            reasons.append(_reason("RECENTLY_PLAYED", "Recently played penalty", -0.35))
        score += rng.uniform(-0.015, 0.015)
        if not reasons:
            reasons.append(_reason("COLD_START", "Cold-start catalog variety", 0.0))
        result.append(Candidate(track, score, familiarity, reasons))
    return result


def generate_playlist(
    owner: User,
    *,
    activity_kind: str,
    duration_minutes: int,
    offline_quota_bytes: int | None = None,
    target_energy: float,
    discovery: float,
    seed: int,
    context_snapshot: ContextSnapshot | None = None,
    source_version: GeneratedPlaylist | None = None,
) -> GeneratedPlaylist:
    place = (
        str(context_snapshot.geofence_reference)
        if context_snapshot and context_snapshot.geofence_reference
        else ""
    )
    candidates = _candidates(owner, activity_kind, place, discovery, seed)
    target_ms = duration_minutes * 60_000
    average_ms = (
        sum(item.track.audio_file.duration_ms for item in candidates) / len(candidates)
        if candidates
        else 0
    )
    selected: list[tuple[Candidate, float, float, list[dict[str, Any]]]] = []
    total_ms = 0
    total_bytes = 0
    remaining = list(candidates)
    while remaining:
        if offline_quota_bytes is None:
            if selected and total_ms >= target_ms - average_ms / 2:
                break
            eligible = remaining
            progress = min(1.0, total_ms / target_ms) if target_ms else 0.0
        else:
            capacity = offline_quota_bytes - total_bytes
            eligible = [
                candidate
                for candidate in remaining
                if candidate.track.audio_file.size_bytes <= capacity
            ]
            if not eligible:
                break
            progress = min(1.0, total_bytes / offline_quota_bytes)
        energy_target = _energy_target(activity_kind, target_energy, progress, len(selected))
        last_artists = {item[0].track.artist_id for item in selected[-3:]}
        last_albums = {item[0].track.album_id for item in selected[-2:] if item[0].track.album_id}
        ranked = []
        for candidate in eligible:
            energy = float(candidate.track.energy) if candidate.track.energy is not None else 0.5
            energy_score = (1.0 - abs(energy - energy_target)) * 0.18
            duration_fit = (
                -abs((target_ms - total_ms) - candidate.track.audio_file.duration_ms)
                / max(target_ms, 1)
                * 0.10
            )
            spacing = 0.0
            if selected and candidate.track.artist_id == selected[-1][0].track.artist_id:
                spacing -= 10.0
            elif candidate.track.artist_id in last_artists:
                spacing -= 0.60
            if candidate.track.album_id and candidate.track.album_id in last_albums:
                spacing -= 0.25
            ranked.append(
                (
                    candidate.base_score + energy_score + duration_fit + spacing,
                    candidate,
                    energy_score,
                    spacing,
                )
            )
        ranked.sort(key=lambda item: (-item[0], str(item[1].track.id)))
        score, chosen, energy_score, spacing = ranked[0]
        reasons = list(chosen.reasons)
        if chosen.track.energy is None:
            reasons.append(
                _reason("ENERGY_UNKNOWN", "No audio energy feature; neutral fallback", energy_score)
            )
        else:
            reasons.append(
                _reason("ENERGY_MATCH", "Fits this point in the activity curve", energy_score)
            )
        if spacing:
            reasons.append(_reason("SPACING_PENALTY", "Artist or album appeared recently", spacing))
        selected.append((chosen, score, energy_target, reasons))
        total_ms += chosen.track.audio_file.duration_ms
        total_bytes += chosen.track.audio_file.size_bytes
        remaining.remove(chosen)
    inputs = {
        "activity_kind": activity_kind,
        "duration_minutes": duration_minutes,
        "offline_quota_bytes": offline_quota_bytes,
        "target_energy": round(target_energy, 4),
        "discovery": round(discovery, 4),
        "seed": seed,
        "context_snapshot_id": str(context_snapshot.id) if context_snapshot else None,
        "model_version": GENERATOR_VERSION,
    }
    digest = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
    with transaction.atomic():
        playlist = GeneratedPlaylist.objects.create(
            owner=owner,
            context_snapshot=context_snapshot,
            source_version=source_version,
            activity_kind=activity_kind,
            geofence_reference=place or None,
            requested_duration_minutes=duration_minutes,
            actual_duration_ms=total_ms,
            target_energy=Decimal(f"{target_energy:.2f}"),
            discovery=Decimal(f"{discovery:.2f}"),
            seed=seed,
            model_version=GENERATOR_VERSION,
            input_digest=digest,
        )
        GeneratedPlaylistTrack.objects.bulk_create(
            [
                GeneratedPlaylistTrack(
                    playlist=playlist,
                    track=item.track,
                    position=position,
                    score=Decimal(f"{score:.5f}"),
                    target_energy=Decimal(f"{energy:.2f}"),
                    reasons=reasons,
                )
                for position, (item, score, energy, reasons) in enumerate(selected)
            ]
        )
    return playlist


def regenerate_playlist(
    owner: User, source: GeneratedPlaylist, seed: int | None = None
) -> GeneratedPlaylist:
    return generate_playlist(
        owner,
        activity_kind=source.activity_kind,
        duration_minutes=source.requested_duration_minutes,
        target_energy=float(source.target_energy),
        discovery=float(source.discovery),
        seed=seed if seed is not None else source.seed + 1,
        context_snapshot=source.context_snapshot,
        source_version=source,
    )


def replace_track(owner: User, source: GeneratedPlaylist, position: int) -> GeneratedPlaylist:
    original = list(
        source.items.select_related("track", "track__artist", "track__album", "track__audio_file")
    )
    if position < 0 or position >= len(original):
        raise ValueError("Playlist position not found")
    replacement_pool = _candidates(
        owner,
        source.activity_kind,
        str(source.geofence_reference or ""),
        float(source.discovery),
        source.seed + position + 1,
    )
    used = {item.track_id for item in original}
    replacement = next(
        (
            item
            for item in sorted(
                replacement_pool, key=lambda item: (-item.base_score, str(item.track.id))
            )
            if item.track.id not in used
        ),
        None,
    )
    if replacement is None:
        raise ValueError("No eligible replacement track is available")
    with transaction.atomic():
        version = GeneratedPlaylist.objects.create(
            owner=owner,
            context_snapshot=source.context_snapshot,
            source_version=source,
            activity_kind=source.activity_kind,
            geofence_reference=source.geofence_reference,
            requested_duration_minutes=source.requested_duration_minutes,
            actual_duration_ms=source.actual_duration_ms
            - original[position].track.audio_file.duration_ms
            + replacement.track.audio_file.duration_ms,
            target_energy=source.target_energy,
            discovery=source.discovery,
            seed=source.seed,
            model_version=source.model_version,
            input_digest=hashlib.sha256(
                f"{source.input_digest}:replace:{position}:{replacement.track.id}".encode()
            ).hexdigest(),
        )
        GeneratedPlaylistTrack.objects.bulk_create(
            [
                GeneratedPlaylistTrack(
                    playlist=version,
                    track=replacement.track if index == position else item.track,
                    position=index,
                    score=Decimal(f"{replacement.base_score:.5f}")
                    if index == position
                    else item.score,
                    target_energy=item.target_energy,
                    reasons=[
                        _reason("USER_REPLACEMENT", "Replaced at your request", 1.0),
                        *replacement.reasons,
                    ]
                    if index == position
                    else item.reasons,
                )
                for index, item in enumerate(original)
            ]
        )
    return version
