import hashlib
import os
import shutil
import uuid
from collections.abc import Iterator
from contextlib import AbstractContextManager, contextmanager
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import BinaryIO, Protocol, cast

from django.conf import settings


class StorageError(RuntimeError):
    """Media storage operation failed."""


@dataclass(frozen=True)
class StorageHealth:
    readable: bool
    writable: bool
    free_bytes: int


class MediaStorage(Protocol):
    backend_id: str

    def publish(self, source: Path, object_key: str, checksum: str) -> bool: ...

    def open(self, object_key: str, mode: str = "rb") -> BinaryIO: ...

    def exists(self, object_key: str) -> bool: ...

    def size(self, object_key: str) -> int: ...

    def delete(self, object_key: str) -> None: ...

    def verify(self, object_key: str, checksum: str) -> bool: ...

    def health(self) -> StorageHealth: ...

    def lock(self, name: str) -> AbstractContextManager[None]: ...


def _safe_key(object_key: str) -> PurePosixPath:
    key = PurePosixPath(object_key)
    if key.is_absolute() or not key.parts or any(part in {"", ".", ".."} for part in key.parts):
        raise StorageError("Invalid storage object key")
    return key


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class FilesystemStorage:
    def __init__(self, root: Path, backend_id: str) -> None:
        self.root = root.resolve()
        self.backend_id = backend_id

    def _path(self, object_key: str) -> Path:
        key = _safe_key(object_key)
        path = self.root.joinpath(*key.parts)
        if not path.is_relative_to(self.root):
            raise StorageError("Storage path escaped configured root")
        return path

    def publish(self, source: Path, object_key: str, checksum: str) -> bool:
        destination = self._path(object_key)
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            if not self.verify(object_key, checksum):
                raise StorageError("Existing object checksum does not match its key")
            return False

        temporary = destination.with_name(f".{destination.name}.{uuid.uuid4().hex}.tmp")
        try:
            with source.open("rb") as incoming, temporary.open("xb") as outgoing:
                shutil.copyfileobj(incoming, outgoing, length=1024 * 1024)
                outgoing.flush()
                os.fsync(outgoing.fileno())
            if sha256_file(temporary) != checksum:
                raise StorageError("Published object failed checksum verification")
            os.replace(temporary, destination)
            return True
        finally:
            temporary.unlink(missing_ok=True)

    def open(self, object_key: str, mode: str = "rb") -> BinaryIO:
        if mode not in {"rb"}:
            raise StorageError("Media objects are immutable and read-only")
        return cast(BinaryIO, self._path(object_key).open(mode))

    def exists(self, object_key: str) -> bool:
        return self._path(object_key).is_file()

    def size(self, object_key: str) -> int:
        return self._path(object_key).stat().st_size

    def delete(self, object_key: str) -> None:
        self._path(object_key).unlink(missing_ok=True)

    def verify(self, object_key: str, checksum: str) -> bool:
        path = self._path(object_key)
        return path.is_file() and sha256_file(path) == checksum

    def health(self) -> StorageHealth:
        self.root.mkdir(parents=True, exist_ok=True)
        probe = self.root / f".health-{uuid.uuid4().hex}"
        writable = False
        try:
            probe.write_bytes(b"umusic")
            writable = probe.read_bytes() == b"umusic"
        except OSError:
            writable = False
        finally:
            probe.unlink(missing_ok=True)
        usage = shutil.disk_usage(self.root)
        return StorageHealth(
            readable=os.access(self.root, os.R_OK), writable=writable, free_bytes=usage.free
        )

    @contextmanager
    def lock(self, name: str) -> Iterator[None]:
        import fcntl

        lock_directory = self.root / ".locks"
        lock_directory.mkdir(parents=True, exist_ok=True)
        lock_path = lock_directory / f"{hashlib.sha256(name.encode()).hexdigest()}.lock"
        with lock_path.open("a+b") as lock_file:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)


class LocalFilesystemStorage(FilesystemStorage):
    def __init__(self, root: Path) -> None:
        super().__init__(root, "local")


class MountedSharedFilesystemStorage(FilesystemStorage):
    def __init__(self, root: Path) -> None:
        super().__init__(root, "mounted")


def get_media_storage() -> MediaStorage:
    return get_storage_for_backend(settings.UMUSIC_STORAGE_BACKEND)


def get_storage_for_backend(backend: str) -> MediaStorage:
    if backend == "local":
        return LocalFilesystemStorage(settings.MEDIA_ROOT)
    if backend == "mounted":
        return MountedSharedFilesystemStorage(settings.MEDIA_ROOT)
    raise StorageError(f"Unsupported media storage backend: {backend}")


def audio_object_key(checksum: str) -> str:
    return f"audio/sha256/{checksum[:2]}/{checksum[2:4]}/{checksum}.mp3"


def artwork_object_key(checksum: str, extension: str) -> str:
    return f"artwork/sha256/{checksum[:2]}/{checksum[2:4]}/{checksum}.{extension}"
