from pathlib import Path

from django.conf import settings


def enabled_adapters() -> set[str]:
    flags = {
        "folder": settings.UMUSIC_FOLDER_IMPORT_ENABLED,
        "taste": settings.UMUSIC_TASTE_IMPORT_ENABLED,
        "youtube": settings.UMUSIC_YOUTUBE_IMPORT_ENABLED,
        "remote": settings.UMUSIC_REMOTE_IMPORT_ENABLED,
    }
    return {name for name, enabled in flags.items() if enabled}


def resolve_import_path(value: str) -> Path:
    candidate = Path(value).resolve()
    if not any(candidate.is_relative_to(root) for root in settings.UMUSIC_IMPORT_ROOTS):
        raise ValueError("Path is outside configured import roots")
    if not candidate.is_dir():
        raise ValueError("Import path is not a directory")
    return candidate
