import csv
import ipaddress
import json
import re
import socket
import subprocess
import tempfile
from io import StringIO
from pathlib import Path
from typing import Any, cast, no_type_check
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

from django.conf import settings
from django.utils import timezone
from mutagen.id3 import (  # type: ignore[attr-defined]
    COMM,
    TALB,
    TCON,
    TDRC,
    TIT2,
    TPE1,
    TPE2,
    TPOS,
    TRCK,
    WOAS,
)
from mutagen.mp3 import MP3

from umusic.apps.accounts.models import User
from umusic.apps.imports.models import AdapterJob, RemoteImportItem
from umusic.apps.library.models import AuditEvent

from .adapter_services import _ingest_path

YOUTUBE_HOSTS = {"youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"}
ALLOWED_CONTENT_TYPES = {"audio/mpeg", "audio/mp3", "application/octet-stream"}


def parse_remote_urls(value: str) -> list[str]:
    urls = [cell.strip() for row in csv.reader(StringIO(value)) for cell in row if cell.strip()]
    if not urls:
        raise ValueError("Provide at least one URL")
    if len(urls) > settings.UMUSIC_REMOTE_IMPORT_MAX_ITEMS:
        raise ValueError(
            f"A batch may contain at most {settings.UMUSIC_REMOTE_IMPORT_MAX_ITEMS} URLs"
        )
    if len(set(urls)) != len(urls):
        raise ValueError("Duplicate URLs are not allowed in one batch")
    return urls


def _validate_public_https(url: str) -> tuple[str, str]:
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("Only credential-free HTTPS URLs are accepted")
    try:
        addresses = socket.getaddrinfo(parsed.hostname, parsed.port or 443, type=socket.SOCK_STREAM)
    except socket.gaierror as error:
        raise ValueError("URL hostname could not be resolved") from error
    for address in addresses:
        ip = ipaddress.ip_address(address[4][0])
        if not ip.is_global:
            raise ValueError("Private, local, and reserved URL targets are not accepted")
    return parsed.hostname.lower(), parsed.path


def create_remote_import(owner: User, value: str, attested: bool) -> AdapterJob:
    if not settings.UMUSIC_REMOTE_IMPORT_ENABLED:
        raise PermissionError("Remote import is disabled")
    urls = parse_remote_urls(value)
    classified: list[tuple[str, str, str]] = []
    for url in urls:
        host, path = _validate_public_https(url)
        kind = (
            RemoteImportItem.Kind.YOUTUBE
            if host in YOUTUBE_HOSTS
            else RemoteImportItem.Kind.DIRECT_MP3
        )
        if kind == RemoteImportItem.Kind.YOUTUBE:
            if not settings.UMUSIC_YOUTUBE_IMPORT_ENABLED:
                raise PermissionError("YouTube import is disabled")
            if not attested:
                raise PermissionError("Authorization attestation is required for YouTube URLs")
        elif not path.lower().endswith(".mp3"):
            raise ValueError("Direct URLs must end with .mp3")
        classified.append((url, host, kind))
    job = AdapterJob.objects.create(
        owner=owner,
        adapter=AdapterJob.Adapter.REMOTE,
        status=AdapterJob.Status.PENDING,
        operator_attested=attested,
        request={"item_count": len(classified)},
        provenance={"source_hosts": sorted({host for _, host, _ in classified})},
    )
    RemoteImportItem.objects.bulk_create(
        [
            RemoteImportItem(
                job=job,
                position=position,
                source_url=url,
                source_host=host,
                kind=kind,
            )
            for position, (url, host, kind) in enumerate(classified, start=1)
        ]
    )
    from umusic.apps.imports.tasks import process_remote_import

    process_remote_import.delay(str(job.id))
    return job


class SafeRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        _validate_public_https(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _download_direct(url: str, destination: Path) -> None:
    _validate_public_https(url)
    opener = build_opener(SafeRedirectHandler())
    request = Request(url, headers={"User-Agent": "uMusic/1.0"})
    with opener.open(request, timeout=30) as response, destination.open("xb") as output:
        content_type = response.headers.get_content_type()
        if content_type not in ALLOWED_CONTENT_TYPES:
            raise ValueError("Remote response is not MP3 audio")
        content_length = response.headers.get("Content-Length")
        if content_length and int(content_length) > settings.UMUSIC_MAX_UPLOAD_BYTES:
            raise ValueError("Remote MP3 exceeds the configured size limit")
        downloaded = 0
        while chunk := response.read(64 * 1024):
            downloaded += len(chunk)
            if downloaded > settings.UMUSIC_MAX_UPLOAD_BYTES:
                raise ValueError("Remote MP3 exceeds the configured size limit")
            output.write(chunk)


def _metadata_text(metadata: dict[str, Any], *keys: str) -> str | None:
    for key in keys:
        value = metadata.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def _youtube_filename(artist: str, title: str) -> str:
    value = re.sub(r'[\\/:*?"<>|\x00-\x1f]+', "-", f"{artist} - {title}")
    value = re.sub(r"\s+", " ", value).strip(" .-")[:240]
    return f"{value or 'YouTube song'}.mp3"


@no_type_check
def _inject_youtube_id3(path: Path, metadata: dict[str, Any], source_url: str) -> Path:
    title = _metadata_text(metadata, "track", "title") or path.stem
    artist = _metadata_text(metadata, "artist", "creator", "uploader", "channel")
    artist = artist or "Unknown Artist"
    album = _metadata_text(metadata, "album", "playlist_title", "playlist")
    album_artist = _metadata_text(metadata, "album_artist") or artist
    date = _metadata_text(metadata, "release_date", "upload_date", "release_year")
    if date and len(date) == 8 and date.isdigit():
        date = f"{date[:4]}-{date[4:6]}-{date[6:]}"
    genres = metadata.get("genre") or metadata.get("categories") or metadata.get("tags") or []
    if isinstance(genres, str):
        genres = [genres]
    genre = "; ".join(str(item) for item in genres[:5] if str(item).strip())
    audio = MP3(path)
    if audio.tags is None:
        audio.add_tags()
    assert audio.tags is not None
    frames = [TIT2(encoding=3, text=title), TPE1(encoding=3, text=artist)]
    if album:
        frames.extend([TALB(encoding=3, text=album), TPE2(encoding=3, text=album_artist)])
    if date:
        frames.append(TDRC(encoding=3, text=date))
    if genre:
        frames.append(TCON(encoding=3, text=genre))
    if metadata.get("track_number"):
        frames.append(TRCK(encoding=3, text=str(metadata["track_number"])))
    if metadata.get("disc_number"):
        frames.append(TPOS(encoding=3, text=str(metadata["disc_number"])))
    for frame_id in ("TIT2", "TPE1", "TPE2", "TALB", "TDRC", "TCON", "TRCK", "TPOS", "WOAS"):
        audio.tags.delall(frame_id)
    for frame in frames:
        audio.tags.add(frame)
    audio.tags.add(WOAS(url=source_url))
    video_id = str(metadata.get("id") or "")
    description = f"Imported from YouTube; video_id={video_id}"[:255]
    audio.tags.delall("COMM:YouTube source:eng")
    audio.tags.add(COMM(encoding=3, lang="eng", desc="YouTube source", text=description))
    audio.save(v2_version=3)
    destination = path.with_name(_youtube_filename(artist, title))
    path.rename(destination)
    return destination


def _download_youtube(url: str, directory: Path) -> Path:
    output = str(directory / "%(id)s.%(ext)s")
    result = subprocess.run(
        [
            settings.UMUSIC_YTDLP_PATH,
            "--ignore-config",
            "--no-playlist",
            "--no-remote-components",
            "--max-filesize",
            str(settings.UMUSIC_MAX_UPLOAD_BYTES),
            "--restrict-filenames",
            "-x",
            "--audio-format",
            "mp3",
            "--audio-quality",
            "0",
            "--embed-metadata",
            "--embed-thumbnail",
            "--print-json",
            "-o",
            output,
            url,
        ],
        check=True,
        timeout=900,
        capture_output=True,
        text=True,
    )
    files = list(directory.glob("*.mp3"))
    if len(files) != 1:
        raise ValueError("YouTube source did not produce one MP3")
    lines = [line for line in result.stdout.splitlines() if line.strip().startswith("{")]
    if not lines:
        raise ValueError("YouTube source did not return metadata")
    try:
        metadata = json.loads(lines[-1])
    except json.JSONDecodeError as error:
        raise ValueError("YouTube metadata could not be parsed") from error
    return cast(Path, _inject_youtube_id3(files[0], metadata, url))


def run_remote_import(job: AdapterJob) -> AdapterJob:
    if job.status not in {AdapterJob.Status.PENDING, AdapterJob.Status.FAILED}:
        return job
    job.status = AdapterJob.Status.RUNNING
    job.error = ""
    job.save(update_fields=["status", "error"])
    imported = 0
    failures = 0
    for item in job.remote_items.all():
        item.status = AdapterJob.Status.RUNNING
        item.save(update_fields=["status"])
        try:
            with tempfile.TemporaryDirectory() as directory_name:
                directory = Path(directory_name)
                if item.kind == RemoteImportItem.Kind.YOUTUBE:
                    path = _download_youtube(item.source_url, directory)
                else:
                    path = directory / f"remote-{item.position}.mp3"
                    _download_direct(item.source_url, path)
                item.imported = _ingest_path(path, job.owner)
                imported += int(item.imported)
                item.status = AdapterJob.Status.COMPLETED
        except Exception as error:
            failures += 1
            item.status = AdapterJob.Status.FAILED
            item.error = f"{type(error).__name__}: import failed"[:500]
        item.completed_at = timezone.now()
        item.save(update_fields=["status", "imported", "error", "completed_at"])
    job.imported_count = imported
    job.status = (
        AdapterJob.Status.FAILED
        if failures == job.remote_items.count()
        else AdapterJob.Status.PARTIAL
        if failures
        else AdapterJob.Status.COMPLETED
    )
    job.error = f"{failures} item(s) failed" if failures else ""
    job.completed_at = timezone.now()
    job.save(update_fields=["imported_count", "status", "error", "completed_at"])
    AuditEvent.objects.create(
        actor=job.owner,
        action="adapter.remote.completed",
        target_type="adapter_job",
        target_id=str(job.id),
        metadata={"status": job.status, "imported": imported, "failed": failures},
    )
    return job
