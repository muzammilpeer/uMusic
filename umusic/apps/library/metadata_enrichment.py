import json
import re
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from django.conf import settings
from django.utils import timezone

from umusic.apps.library.models import Track


MUSICBRAINZ_ENDPOINT = "https://musicbrainz.org/ws/2/recording/"


@dataclass(frozen=True)
class EnrichmentResult:
    matched: bool
    applied: bool
    score: int
    recording_id: str | None


def filename_query(track: Track) -> str:
    stem = Path(track.audio_file.original_filename).stem
    stem = re.sub(r"[_]+", " ", stem)
    stem = re.sub(r"^\s*\d+[\s.()_-]+", "", stem)
    stem = re.sub(r"\s+", " ", stem).strip()
    parts = [f'recording:"{stem}"']
    artist = track.artist.name.strip()
    if artist and artist.casefold() != "unknown artist":
        parts.append(f'artist:"{artist}"')
    return " AND ".join(parts)


def lookup_musicbrainz(track: Track, timeout: int = 20) -> dict[str, Any] | None:
    params = urllib.parse.urlencode({"query": filename_query(track), "fmt": "json", "limit": 5})
    user_agent = getattr(
        settings,
        "UMUSIC_METADATA_USER_AGENT",
        "uMusic/2.0 (https://umusic.muzammilpeer.uk)",
    )
    request = urllib.request.Request(
        f"{MUSICBRAINZ_ENDPOINT}?{params}",
        headers={"Accept": "application/json", "User-Agent": user_agent},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.load(response)
    recordings = payload.get("recordings", [])
    return recordings[0] if recordings else None


def enrich_track(track: Track, *, apply_threshold: int = 95) -> EnrichmentResult:
    match = lookup_musicbrainz(track)
    if not match:
        track.external_metadata = {
            "provider": "musicbrainz",
            "query": filename_query(track),
            "status": "unmatched",
            "checked_at": timezone.now().isoformat(),
        }
        track.save(update_fields=["external_metadata", "updated_at"])
        return EnrichmentResult(False, False, 0, None)

    score = max(0, min(int(match.get("score", 0)), 100))
    releases = match.get("releases") or []
    release = releases[0] if releases else {}
    first_date = str(match.get("first-release-date") or release.get("date") or "")
    year_match = re.match(r"^(\d{4})", first_date)
    year = int(year_match.group(1)) if year_match else None
    genres = [
        str(item.get("name", "")).strip()
        for item in (match.get("genres") or match.get("tags") or [])
        if str(item.get("name", "")).strip()
    ][:20]
    artist_credit = "".join(
        str(item.get("name") or item.get("artist", {}).get("name") or "")
        + str(item.get("joinphrase") or "")
        for item in match.get("artist-credit", [])
    ).strip()
    applied = score >= apply_threshold
    changed: list[str] = ["external_metadata", "updated_at"]
    if applied and track.year is None and year is not None and 1000 <= year <= 9999:
        track.year = year
        changed.append("year")
    if applied and not track.genres and genres:
        track.genres = genres
        changed.append("genres")
    track.external_metadata = {
        "provider": "musicbrainz",
        "status": "applied" if applied else "needs_review",
        "query": filename_query(track),
        "score": score,
        "checked_at": timezone.now().isoformat(),
        "recording": {
            "id": match.get("id"),
            "title": match.get("title"),
            "artist": artist_credit,
            "first_release_date": first_date or None,
            "release_id": release.get("id"),
            "release_title": release.get("title"),
            "country": release.get("country"),
            "genres": genres,
            "isrcs": list(match.get("isrcs") or [])[:20],
        },
    }
    track.save(update_fields=list(dict.fromkeys(changed)))
    return EnrichmentResult(True, applied, score, match.get("id"))
