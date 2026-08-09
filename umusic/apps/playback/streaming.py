import re
from collections.abc import Iterator
from typing import BinaryIO
from urllib.parse import quote

from django.conf import settings
from django.http import HttpRequest, HttpResponse, StreamingHttpResponse
from django.http.response import HttpResponseBase
from django.shortcuts import get_object_or_404

from umusic.apps.library.services import playable_tracks
from umusic.apps.library.storage import get_storage_for_backend

RANGE_PATTERN = re.compile(r"^bytes=(\d*)-(\d*)$")


def _chunks(source: BinaryIO, start: int, length: int) -> Iterator[bytes]:
    try:
        source.seek(start)
        remaining = length
        while remaining:
            chunk = source.read(min(64 * 1024, remaining))
            if not chunk:
                break
            remaining -= len(chunk)
            yield chunk
    finally:
        source.close()


def _range(value: str, size: int) -> tuple[int, int] | None:
    match = RANGE_PATTERN.fullmatch(value.strip())
    if not match or size <= 0:
        return None
    first, last = match.groups()
    if not first and not last:
        return None
    if not first:
        suffix = int(last)
        if suffix <= 0:
            return None
        return max(0, size - suffix), size - 1
    start = int(first)
    end = int(last) if last else size - 1
    if start >= size or end < start:
        return None
    return start, min(end, size - 1)


def stream_track(request: HttpRequest, track_id: str) -> HttpResponseBase:
    if not request.user.is_authenticated:
        return HttpResponse(status=401)
    track = get_object_or_404(
        playable_tracks(request.user).select_related("audio_file"), id=track_id
    )
    audio = track.audio_file
    storage = get_storage_for_backend(audio.storage_backend)
    if not storage.exists(audio.object_key):
        return HttpResponse(status=404)
    size = storage.size(audio.object_key)
    headers = {
        "Accept-Ranges": "bytes",
        "Cache-Control": "private, max-age=3600",
        "ETag": f'"{audio.checksum}"',
        "Content-Type": "audio/mpeg",
        "Content-Disposition": f"inline; filename*=UTF-8''{quote(audio.original_filename)}",
    }
    range_header = request.headers.get("Range")
    start, end, status = 0, size - 1, 200
    if range_header:
        selected = _range(range_header, size)
        if selected is None:
            response = HttpResponse(status=416)
            response["Content-Range"] = f"bytes */{size}"
            response["Accept-Ranges"] = "bytes"
            return response
        start, end = selected
        status = 206
        headers["Content-Range"] = f"bytes {start}-{end}/{size}"
    length = end - start + 1
    headers["Content-Length"] = str(length)
    if settings.UMUSIC_USE_INTERNAL_REDIRECT and status == 200:
        response = HttpResponse(status=200, headers=headers)
        prefix = settings.UMUSIC_INTERNAL_MEDIA_PREFIX.rstrip("/")
        response["X-Accel-Redirect"] = f"{prefix}/{audio.object_key}"
        return response
    return StreamingHttpResponse(
        _chunks(storage.open(audio.object_key), start, length), status=status, headers=headers
    )
