import hashlib
import json
import logging
import re
import shutil
import subprocess
import tempfile
import unicodedata
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, no_type_check

from django.conf import settings
from django.core.files.uploadedfile import UploadedFile
from django.db import models, transaction
from django.db.models import Q, QuerySet
from django.utils import timezone
from mutagen.id3 import (  # type: ignore[attr-defined]
    APIC,
    TALB,
    TCON,
    TDRC,
    TIT2,
    TPE1,
    TPE2,
    TPOS,
    TRCK,
)
from mutagen.mp3 import MP3, HeaderNotFoundError

from umusic.apps.library.models import (
    Album,
    Artist,
    Artwork,
    AudioFile,
    AuditEvent,
    ImportJob,
    LibraryMembership,
    Track,
)
from umusic.apps.library.storage import (
    MediaStorage,
    StorageError,
    artwork_object_key,
    audio_object_key,
    get_media_storage,
    get_storage_for_backend,
    sha256_file,
)

logger = logging.getLogger(__name__)


class ImportFailure(RuntimeError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def accessible_tracks(owner: Any) -> QuerySet[Track]:
    return Track.objects.filter(
        is_active=True,
        memberships__owner=owner,
        memberships__state=LibraryMembership.State.ACTIVE,
    ).distinct()


def playable_tracks(owner: Any) -> QuerySet[Track]:
    """Tracks in the private library or a currently authorized shared playlist."""
    return Track.objects.filter(is_active=True).filter(
        Q(
            memberships__owner=owner,
            memberships__state=LibraryMembership.State.ACTIVE,
        )
        | Q(playlisttrack__playlist__owner=owner)
        | Q(
            playlisttrack__playlist__access_grants__user=owner,
            playlisttrack__playlist__access_grants__state="active",
        )
    ).distinct()


def logical_library_bytes(owner: Any) -> int:
    return int(
        LibraryMembership.objects.filter(
            owner=owner, state=LibraryMembership.State.ACTIVE
        ).aggregate(total=models.Sum("track__audio_file__size_bytes"))["total"]
        or 0
    )


def add_library_membership(
    owner: Any, track: Track, source: str = LibraryMembership.Source.UPLOAD
) -> LibraryMembership:
    membership = LibraryMembership.objects.filter(owner=owner, track=track).first()
    if membership and membership.state == LibraryMembership.State.ACTIVE:
        return membership
    current_bytes = logical_library_bytes(owner)
    if current_bytes + track.audio_file.size_bytes > owner.storage_quota_bytes:
        raise ImportFailure("QUOTA_EXCEEDED", "This import exceeds your library storage quota.")
    membership, created = LibraryMembership.objects.get_or_create(
        owner=owner,
        track=track,
        defaults={"state": LibraryMembership.State.ACTIVE, "source": source},
    )
    if not created:
        membership.state = LibraryMembership.State.ACTIVE
        membership.source = source
        membership.removed_at = None
        membership.save(update_fields=["state", "source", "removed_at", "updated_at"])
    AuditEvent.objects.create(
        actor=owner,
        action="library.membership.added",
        target_type="track",
        target_id=str(track.id),
        metadata={"source": source, "size_bytes": track.audio_file.size_bytes},
    )
    return membership


@dataclass(frozen=True)
class ArtworkMetadata:
    content: bytes
    mime_type: str
    extension: str


@dataclass(frozen=True)
class AudioMetadata:
    title: str
    artist: str
    album: str | None
    album_artist: str | None
    duration_ms: int
    bitrate: int | None
    sample_rate: int | None
    track_number: int | None
    disc_number: int | None
    year: int | None
    genres: list[str]
    artwork: ArtworkMetadata | None


def normalize_name(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold().strip()
    return re.sub(r"\s+", " ", normalized)


def _first_text(tags: Any, frame_type: type[Any]) -> str | None:
    if tags is None:
        return None
    frames = tags.getall(frame_type.__name__)
    if not frames or not frames[0].text:
        return None
    value = str(frames[0].text[0]).strip()
    return value or None


def _number_prefix(value: str | None) -> int | None:
    if not value:
        return None
    match = re.match(r"^(\d+)", value)
    return int(match.group(1)) if match else None


def _year(value: str | None) -> int | None:
    if not value:
        return None
    match = re.search(r"\b(\d{4})\b", value)
    return int(match.group(1)) if match else None


def inspect_mp3(path: Path, original_filename: str) -> AudioMetadata:
    if Path(original_filename).suffix.casefold() != ".mp3":
        raise ImportFailure("INVALID_EXTENSION", "Only files ending in .mp3 are accepted.")

    command = [
        settings.UMUSIC_FFPROBE_PATH,
        "-v",
        "error",
        "-show_entries",
        "format=format_name,duration,bit_rate:stream=codec_type,codec_name,sample_rate",
        "-of",
        "json",
        str(path),
    ]
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ImportFailure("INSPECTION_FAILED", "Unable to inspect the uploaded audio.") from exc
    if result.returncode != 0:
        raise ImportFailure("INVALID_AUDIO_FORMAT", "The uploaded file is not valid MP3 audio.")

    try:
        probe = json.loads(result.stdout)
        streams = probe.get("streams", [])
        audio_stream = next(stream for stream in streams if stream.get("codec_type") == "audio")
        format_names = str(probe["format"].get("format_name", "")).split(",")
        if audio_stream.get("codec_name") != "mp3" or "mp3" not in format_names:
            raise KeyError("not mp3")
        duration_ms = round(float(probe["format"]["duration"]) * 1000)
        if duration_ms <= 0:
            raise KeyError("invalid duration")
    except (KeyError, StopIteration, TypeError, ValueError) as exc:
        raise ImportFailure(
            "INVALID_AUDIO_FORMAT", "The uploaded file is not valid MP3 audio."
        ) from exc

    try:
        audio = MP3(path)
    except (HeaderNotFoundError, OSError) as exc:
        raise ImportFailure(
            "INVALID_AUDIO_FORMAT", "The uploaded file has invalid MP3 frames."
        ) from exc

    tags = audio.tags
    title = _first_text(tags, TIT2) or Path(original_filename).stem
    artist = _first_text(tags, TPE1) or "Unknown Artist"
    album = _first_text(tags, TALB)
    album_artist = _first_text(tags, TPE2)
    track_number = _number_prefix(_first_text(tags, TRCK))
    disc_number = _number_prefix(_first_text(tags, TPOS))
    year = _year(_first_text(tags, TDRC))
    genre_text = _first_text(tags, TCON) or ""
    genres = list(
        dict.fromkeys(part.strip()[:100] for part in re.split(r"[;/]", genre_text) if part.strip())
    )

    artwork = None
    if tags:
        pictures = tags.getall(APIC.__name__)
        if pictures:
            picture = pictures[0]
            extensions = {"image/jpeg": "jpg", "image/png": "png"}
            extension = extensions.get(picture.mime.casefold())
            if extension and picture.data:
                artwork = ArtworkMetadata(bytes(picture.data), picture.mime.casefold(), extension)

    bitrate_raw = probe["format"].get("bit_rate") or audio_stream.get("bit_rate")
    sample_rate_raw = audio_stream.get("sample_rate")
    return AudioMetadata(
        title=title[:255],
        artist=artist[:255],
        album=album[:255] if album else None,
        album_artist=album_artist[:255] if album_artist else None,
        duration_ms=duration_ms,
        bitrate=int(bitrate_raw) if bitrate_raw else None,
        sample_rate=int(sample_rate_raw) if sample_rate_raw else None,
        track_number=track_number,
        disc_number=disc_number,
        year=year,
        genres=genres,
        artwork=artwork,
    )


def quarantine_upload(upload: UploadedFile, owner: Any) -> ImportJob:
    filename = Path(upload.name or "upload.mp3").name[:255]
    upload_size = upload.size or 0
    job = ImportJob.objects.create(owner=owner, source_filename=filename, size_bytes=upload_size)
    if upload_size > settings.UMUSIC_MAX_UPLOAD_BYTES:
        job.status = ImportJob.Status.FAILED
        job.error_code = "FILE_TOO_LARGE"
        job.error_message = "The MP3 exceeds the configured upload size limit."
        job.completed_at = timezone.now()
        job.save(update_fields=["status", "error_code", "error_message", "completed_at"])
        return job

    quarantine_root = settings.UMUSIC_QUARANTINE_ROOT
    quarantine_root.mkdir(parents=True, exist_ok=True)
    quarantine_key = f"{job.id.hex}.upload"
    destination = quarantine_root / quarantine_key
    bytes_written = 0
    try:
        with destination.open("xb") as output:
            for chunk in upload.chunks():
                bytes_written += len(chunk)
                if bytes_written > settings.UMUSIC_MAX_UPLOAD_BYTES:
                    raise ImportFailure(
                        "FILE_TOO_LARGE",
                        "The MP3 exceeds the configured upload size limit.",
                    )
                output.write(chunk)
        job.quarantine_key = quarantine_key
        job.size_bytes = bytes_written
        job.save(update_fields=["quarantine_key", "size_bytes"])
    except Exception:
        destination.unlink(missing_ok=True)
        raise
    return job


def _get_artist(name: str) -> Artist:
    normalized = normalize_name(name)
    artist, _ = Artist.objects.get_or_create(
        normalized_name=normalized,
        defaults={"name": name},
    )
    return artist


def _create_artwork(
    metadata: ArtworkMetadata | None,
    storage: MediaStorage,
    quarantine_root: Path,
) -> tuple[Artwork | None, tuple[str, bool] | None]:
    if metadata is None:
        return None, None
    checksum = hashlib.sha256(metadata.content).hexdigest()
    existing = Artwork.objects.filter(checksum=checksum).first()
    if existing:
        return existing, None

    temporary = quarantine_root / f"artwork-{uuid.uuid4().hex}.tmp"
    temporary.write_bytes(metadata.content)
    key = artwork_object_key(checksum, metadata.extension)
    published = False
    try:
        published = storage.publish(temporary, key, checksum)
        artwork, _ = Artwork.objects.get_or_create(
            checksum=checksum,
            defaults={
                "storage_backend": storage.backend_id,
                "object_key": key,
                "mime_type": metadata.mime_type,
                "size_bytes": len(metadata.content),
            },
        )
        return artwork, (key, published)
    except Exception:
        if published:
            storage.delete(key)
        raise
    finally:
        temporary.unlink(missing_ok=True)


def process_import(job: ImportJob, storage: MediaStorage | None = None) -> ImportJob:
    storage = storage or get_media_storage()
    path = settings.UMUSIC_QUARANTINE_ROOT / job.quarantine_key
    if not job.quarantine_key or not path.is_file():
        return _fail_job(job, ImportFailure("MISSING_UPLOAD", "The quarantined upload is missing."))

    job.status = ImportJob.Status.PROCESSING
    job.started_at = timezone.now()
    job.save(update_fields=["status", "started_at"])

    created_audio_key: str | None = None
    created_artwork: tuple[str, bool] | None = None
    try:
        metadata = inspect_mp3(path, job.source_filename)
        checksum = sha256_file(path)
        key = audio_object_key(checksum)
        with storage.lock(checksum):
            existing = AudioFile.objects.select_related("track").filter(checksum=checksum).first()
            if existing:
                add_library_membership(job.owner, existing.track)
                job.status = ImportJob.Status.DUPLICATE
                job.checksum = checksum
                job.track = existing.track
                job.completed_at = timezone.now()
                job.quarantine_key = ""
                job.save(
                    update_fields=["status", "checksum", "track", "completed_at", "quarantine_key"]
                )
                AuditEvent.objects.create(
                    actor=job.owner,
                    action="library.import.duplicate",
                    target_type="track",
                    target_id=str(existing.track.id),
                    metadata={"checksum": checksum, "filename": job.source_filename},
                )
                path.unlink(missing_ok=True)
                return job

            if logical_library_bytes(job.owner) + job.size_bytes > job.owner.storage_quota_bytes:
                raise ImportFailure(
                    "QUOTA_EXCEEDED", "This import exceeds your library storage quota."
                )

            with transaction.atomic():
                published = storage.publish(path, key, checksum)
                if published:
                    created_audio_key = key
                artist = _get_artist(metadata.artist)
                album_artist = (
                    _get_artist(metadata.album_artist) if metadata.album_artist else artist
                )
                album = None
                if metadata.album:
                    album, _ = Album.objects.get_or_create(
                        normalized_title=normalize_name(metadata.album),
                        album_artist=album_artist,
                        defaults={"title": metadata.album, "year": metadata.year},
                    )
                artwork, created_artwork = _create_artwork(
                    metadata.artwork,
                    storage,
                    settings.UMUSIC_QUARANTINE_ROOT,
                )
                audio_file = AudioFile.objects.create(
                    checksum=checksum,
                    storage_backend=storage.backend_id,
                    object_key=key,
                    original_filename=job.source_filename,
                    size_bytes=job.size_bytes,
                    duration_ms=metadata.duration_ms,
                    bitrate=metadata.bitrate,
                    sample_rate=metadata.sample_rate,
                )
                track = Track.objects.create(
                    title=metadata.title,
                    artist=artist,
                    album=album,
                    artwork=artwork,
                    audio_file=audio_file,
                    track_number=metadata.track_number,
                    disc_number=metadata.disc_number,
                    year=metadata.year,
                    genres=metadata.genres,
                )
                add_library_membership(job.owner, track)
                job.status = ImportJob.Status.COMPLETED
                job.checksum = checksum
                job.track = track
                job.completed_at = timezone.now()
                job.quarantine_key = ""
                job.save(
                    update_fields=["status", "checksum", "track", "completed_at", "quarantine_key"]
                )
                AuditEvent.objects.create(
                    actor=job.owner,
                    action="library.import.completed",
                    target_type="track",
                    target_id=str(track.id),
                    metadata={"checksum": checksum, "filename": job.source_filename},
                )
        path.unlink(missing_ok=True)
        return job
    except ImportFailure as exc:
        return _fail_job(job, exc)
    except (OSError, StorageError):
        if created_audio_key:
            storage.delete(created_audio_key)
        if created_artwork and created_artwork[1]:
            storage.delete(created_artwork[0])
        return _fail_job(job, ImportFailure("STORAGE_ERROR", "Unable to store the uploaded MP3."))
    except Exception:
        logger.exception("Unexpected MP3 import failure", extra={"import_job_id": str(job.id)})
        if created_audio_key:
            storage.delete(created_audio_key)
        if created_artwork and created_artwork[1]:
            storage.delete(created_artwork[0])
        return _fail_job(
            job,
            ImportFailure("IMPORT_FAILED", "The MP3 import could not be completed."),
        )


def _fail_job(job: ImportJob, failure: ImportFailure) -> ImportJob:
    if job.quarantine_key:
        (settings.UMUSIC_QUARANTINE_ROOT / job.quarantine_key).unlink(missing_ok=True)
    job.status = ImportJob.Status.FAILED
    job.error_code = failure.code
    job.error_message = failure.message
    job.completed_at = timezone.now()
    job.quarantine_key = ""
    job.save(
        update_fields=["status", "error_code", "error_message", "completed_at", "quarantine_key"]
    )
    AuditEvent.objects.create(
        actor=job.owner,
        action="library.import.failed",
        target_type="import_job",
        target_id=str(job.id),
        metadata={"error_code": failure.code, "filename": job.source_filename},
    )
    return job


def song_filename(artist: str, title: str) -> str:
    value = re.sub(r'[\\/:*?"<>|\x00-\x1f]+', "-", f"{artist} - {title}")
    value = re.sub(r"\s+", " ", value).strip(" .-")[:240]
    return f"{value or 'Song'}.mp3"


def remove_track_from_library(track: Track, actor: Any) -> bool:
    """Remove only the actor's membership; shared catalog media remains intact."""
    with transaction.atomic():
        membership = LibraryMembership.objects.select_for_update().filter(
            owner=actor, track=track, state=LibraryMembership.State.ACTIVE
        ).first()
        if membership is None:
            return False
        membership.state = LibraryMembership.State.REMOVED
        membership.removed_at = timezone.now()
        membership.save(update_fields=["state", "removed_at", "updated_at"])
        from umusic.apps.playlists.models import PlaylistTrack

        PlaylistTrack.objects.filter(playlist__owner=actor, track=track).delete()
        AuditEvent.objects.create(
            actor=actor,
            action="library.membership.removed",
            target_type="track",
            target_id=str(track.id),
            metadata={
                "title": track.title,
                "artist": track.artist.name,
                "size_bytes": track.audio_file.size_bytes,
            },
        )
    return True


@no_type_check
def update_track_metadata(track: Track, owner: Any, values: dict[str, Any]) -> Track:
    title = str(values["title"]).strip()[:255]
    artist_name = str(values["artist"]).strip()[:255]
    album_name = str(values.get("album") or "").strip()[:255]
    genre_values = [
        part.strip()[:100]
        for part in re.split(r"[;,/]", str(values.get("genres") or ""))
        if part.strip()
    ]
    year = values.get("year") or None
    track_number = values.get("track_number") or None
    disc_number = values.get("disc_number") or None
    audio_file = track.audio_file
    storage = get_storage_for_backend(audio_file.storage_backend)
    old_key = audio_file.object_key
    old_checksum = audio_file.checksum
    with tempfile.TemporaryDirectory() as directory_name:
        temporary = Path(directory_name) / "metadata-update.mp3"
        with storage.open(old_key) as source, temporary.open("wb") as destination:
            shutil.copyfileobj(source, destination)
        audio = MP3(temporary)
        if audio.tags is None:
            audio.add_tags()
        assert audio.tags is not None
        replacements: list[Any] = [
            TIT2(encoding=3, text=title),
            TPE1(encoding=3, text=artist_name),
        ]
        if album_name:
            replacements.extend(
                [TALB(encoding=3, text=album_name), TPE2(encoding=3, text=artist_name)]
            )
        if year:
            replacements.append(TDRC(encoding=3, text=str(year)))
        if genre_values:
            replacements.append(TCON(encoding=3, text="; ".join(genre_values)))
        if track_number:
            replacements.append(TRCK(encoding=3, text=str(track_number)))
        if disc_number:
            replacements.append(TPOS(encoding=3, text=str(disc_number)))
        for frame_id in ("TIT2", "TPE1", "TPE2", "TALB", "TDRC", "TCON", "TRCK", "TPOS"):
            audio.tags.delall(frame_id)
        for frame in replacements:
            audio.tags.add(frame)
        audio.save(v2_version=3)
        checksum = sha256_file(temporary)
        duplicate = AudioFile.objects.exclude(id=audio_file.id).filter(checksum=checksum).exists()
        if duplicate:
            raise ImportFailure(
                "DUPLICATE_AUDIO", "These tags would duplicate another stored MP3."
            )
        new_key = audio_object_key(checksum)
        published = storage.publish(temporary, new_key, checksum)
        try:
            with transaction.atomic():
                artist = _get_artist(artist_name)
                album = None
                if album_name:
                    album, _ = Album.objects.get_or_create(
                        normalized_title=normalize_name(album_name),
                        album_artist=artist,
                        defaults={"title": album_name, "year": year},
                    )
                track.title = title
                track.artist = artist
                track.album = album
                track.year = year
                track.track_number = track_number
                track.disc_number = disc_number
                track.genres = list(dict.fromkeys(genre_values))
                track.save(
                    update_fields=[
                        "title", "artist", "album", "year", "track_number", "disc_number",
                        "genres", "updated_at",
                    ]
                )
                audio_file.checksum = checksum
                audio_file.object_key = new_key
                audio_file.original_filename = song_filename(artist_name, title)
                audio_file.size_bytes = temporary.stat().st_size
                audio_file.save(
                    update_fields=["checksum", "object_key", "original_filename", "size_bytes"]
                )
                AuditEvent.objects.create(
                    actor=owner,
                    action="library.track_metadata.updated",
                    target_type="track",
                    target_id=str(track.id),
                    metadata={"old_checksum": old_checksum, "new_checksum": checksum},
                )
        except Exception:
            if published:
                storage.delete(new_key)
            raise
    if old_key != new_key:
        storage.delete(old_key)
    track.refresh_from_db()
    return track
