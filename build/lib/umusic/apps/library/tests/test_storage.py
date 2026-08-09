import hashlib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import pytest

from umusic.apps.library.storage import (
    FilesystemStorage,
    LocalFilesystemStorage,
    MountedSharedFilesystemStorage,
    StorageError,
)


@pytest.fixture(params=["local", "mounted"])
def storage(request: pytest.FixtureRequest, tmp_path: Path) -> FilesystemStorage:
    if request.param == "local":
        return LocalFilesystemStorage(tmp_path / "local")
    return MountedSharedFilesystemStorage(tmp_path / "mounted")


def test_storage_contract_publish_read_verify_delete(
    storage: FilesystemStorage, tmp_path: Path
) -> None:
    source = tmp_path / "source"
    source.write_bytes(b"authorized mp3 placeholder")
    checksum = hashlib.sha256(source.read_bytes()).hexdigest()
    key = f"audio/sha256/{checksum}.mp3"

    assert storage.publish(source, key, checksum) is True
    assert storage.publish(source, key, checksum) is False
    assert storage.exists(key)
    assert storage.size(key) == len(source.read_bytes())
    assert storage.verify(key, checksum)
    with storage.open(key) as stored:
        assert stored.read() == source.read_bytes()
    health = storage.health()
    assert health.readable and health.writable and health.free_bytes > 0
    storage.delete(key)
    assert not storage.exists(key)


def test_storage_rejects_path_traversal(storage: FilesystemStorage) -> None:
    with pytest.raises(StorageError):
        storage.exists("../outside.mp3")


def test_storage_rejects_wrong_checksum(storage: FilesystemStorage, tmp_path: Path) -> None:
    source = tmp_path / "source"
    source.write_bytes(b"content")
    with pytest.raises(StorageError, match="checksum"):
        storage.publish(source, "audio/wrong.mp3", "0" * 64)
    assert not storage.exists("audio/wrong.mp3")


def test_checksum_lock_serializes_concurrent_publish(
    storage: FilesystemStorage, tmp_path: Path
) -> None:
    source = tmp_path / "source"
    source.write_bytes(b"same immutable content")
    checksum = hashlib.sha256(source.read_bytes()).hexdigest()
    key = f"audio/{checksum}.mp3"

    def publish() -> bool:
        with storage.lock(checksum):
            return storage.publish(source, key, checksum)

    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda _: publish(), range(2)))

    assert sorted(results) == [False, True]
