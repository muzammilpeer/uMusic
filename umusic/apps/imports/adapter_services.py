import tempfile
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any, cast

from django.core.files import File
from django.core.files.uploadedfile import UploadedFile
from django.utils import timezone

from umusic.apps.accounts.models import User
from umusic.apps.imports.adapters import enabled_adapters, resolve_import_path
from umusic.apps.imports.models import AdapterJob, TasteCandidate
from umusic.apps.library.models import AuditEvent
from umusic.apps.library.services import (
    accessible_tracks,
    normalize_name,
    process_import,
    quarantine_upload,
)


def _require(adapter: str) -> None:
    if adapter not in enabled_adapters():
        raise PermissionError(f"{adapter} adapter is disabled")


def _ingest_path(path: Path, owner: User) -> bool:
    with path.open("rb") as source:
        job = quarantine_upload(cast(UploadedFile, File(source, name=path.name)), owner)
    return process_import(job).status in {"completed", "duplicate"}


def import_folder(owner: User, folder: str) -> AdapterJob:
    _require("folder")
    root = resolve_import_path(folder)
    job = AdapterJob.objects.create(
        owner=owner, adapter="folder", status="running", request={"folder": str(root)}
    )
    try:
        files = sorted(path for path in root.rglob("*.mp3") if path.is_file())
        job.imported_count = sum(_ingest_path(path, owner) for path in files)
        job.status = "completed"
        job.provenance = {"root": str(root), "files_seen": len(files)}
    except Exception as error:
        job.status, job.error = "failed", str(error)
    job.completed_at = timezone.now()
    job.save()
    AuditEvent.objects.create(
        actor=owner,
        action="adapter.folder.completed",
        target_type="adapter_job",
        target_id=str(job.id),
        metadata={"status": job.status, "count": job.imported_count},
    )
    return job


def import_taste(owner: User, entries: list[dict[str, Any]]) -> AdapterJob:
    _require("taste")
    job = AdapterJob.objects.create(
        owner=owner, adapter="taste", status="running", request={"entry_count": len(entries)}
    )
    tracks = list(accessible_tracks(owner).select_related("artist"))
    for entry in entries:
        artist, title = str(entry.get("artist", "")).strip(), str(entry.get("title", "")).strip()
        exact = next(
            (
                track
                for track in tracks
                if normalize_name(track.artist.name) == normalize_name(artist)
                and normalize_name(track.title) == normalize_name(title)
            ),
            None,
        )
        probable = None
        confidence = 0.0
        if exact is None:
            for track in tracks:
                artist_score = SequenceMatcher(
                    None, normalize_name(artist), normalize_name(track.artist.name)
                ).ratio()
                title_score = SequenceMatcher(
                    None, normalize_name(title), normalize_name(track.title)
                ).ratio()
                score = (artist_score + title_score) / 2
                if score > confidence:
                    probable, confidence = track, score
        state = "exact" if exact else "probable" if confidence >= 0.82 else "unmatched"
        TasteCandidate.objects.create(
            job=job,
            artist=artist[:255],
            title=title[:255],
            duration_ms=entry.get("duration_ms"),
            matched_track=exact or (probable if state == "probable" else None),
            state=state,
            confidence=1 if exact else confidence if state == "probable" else 0,
        )
    job.status, job.imported_count, job.completed_at = "completed", len(entries), timezone.now()
    job.save()
    return job


def confirm_candidate(owner: User, candidate: TasteCandidate, accept: bool) -> TasteCandidate:
    if candidate.job.owner_id != owner.id or candidate.state not in {"probable", "unmatched"}:
        raise ValueError("Candidate cannot be confirmed")
    candidate.state = "confirmed" if accept and candidate.matched_track_id else "rejected"
    candidate.save(update_fields=["state"])
    AuditEvent.objects.create(
        actor=owner,
        action="taste.match.confirmed" if accept else "taste.match.rejected",
        target_type="taste_candidate",
        target_id=str(candidate.id),
        metadata={"track_id": str(candidate.matched_track_id or "")},
    )
    return candidate


def import_youtube(owner: User, url: str, attested: bool) -> AdapterJob:
    _require("youtube")
    if not attested:
        raise PermissionError("Operator authorization attestation is required")
    if not url.startswith(
        ("https://www.youtube.com/", "https://youtube.com/", "https://youtu.be/")
    ):
        raise ValueError("Only public YouTube URLs are accepted")
    if AdapterJob.objects.filter(adapter="youtube", status="running").exists():
        raise RuntimeError("YouTube acquisition concurrency limit reached")
    job = AdapterJob.objects.create(
        owner=owner,
        adapter="youtube",
        status="running",
        operator_attested=True,
        request={"source_host": "youtube.com"},
        provenance={"url": url},
    )
    try:
        with tempfile.TemporaryDirectory() as directory:
            from umusic.apps.imports.remote_services import _download_youtube

            path = _download_youtube(url, Path(directory))
            job.imported_count = int(_ingest_path(path, owner))
        job.status = "completed"
    except Exception as error:
        job.status, job.error = "failed", str(error)
    job.completed_at = timezone.now()
    job.save()
    AuditEvent.objects.create(
        actor=owner,
        action="adapter.youtube.completed",
        target_type="adapter_job",
        target_id=str(job.id),
        metadata={"status": job.status, "attested": True},
    )
    return job
