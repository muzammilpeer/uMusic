import hashlib
import time
import uuid
from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser
from django.db import transaction

from umusic.apps.library.models import Artist, AudioFile, Track


class Command(BaseCommand):
    help = "Generate synthetic tracks and measure the main catalog queries."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("--size", type=int, default=50_000)
        parser.add_argument("--batch-size", type=int, default=2_000)
        parser.add_argument("--max-ms", type=float, default=500.0)
        parser.add_argument(
            "--generate",
            action="store_true",
            help="Add the requested number of synthetic tracks before measuring.",
        )

    def handle(self, *args: Any, **options: Any) -> None:
        size = options["size"]
        batch_size = options["batch_size"]
        if size < 1 or batch_size < 1:
            raise CommandError("--size and --batch-size must be positive")
        if options["generate"]:
            self._generate(size, batch_size)

        timings = {
            "browse": self._measure(
                lambda: list(
                    Track.objects.filter(is_active=True)
                    .select_related("artist", "album", "audio_file")
                    .order_by("artist__name", "title")[:100]
                )
            ),
            "search": self._measure(
                lambda: list(
                    Track.objects.filter(
                        is_active=True, title__icontains="Synthetic"
                    ).select_related("artist")[:100]
                )
            ),
        }
        count = Track.objects.filter(is_active=True).count()
        self.stdout.write(f"active_tracks={count}")
        for name, elapsed_ms in timings.items():
            self.stdout.write(f"{name}_ms={elapsed_ms:.2f}")
        slow = {name: value for name, value in timings.items() if value > options["max_ms"]}
        if slow:
            raise CommandError(f"Catalog query target exceeded: {slow}")

    @staticmethod
    def _measure(operation: Any) -> float:
        started = time.perf_counter()
        operation()
        return (time.perf_counter() - started) * 1_000

    def _generate(self, size: int, batch_size: int) -> None:
        run_id = uuid.uuid4().hex
        artist, _ = Artist.objects.get_or_create(
            normalized_name=f"synthetic-benchmark-{run_id}",
            defaults={"name": f"Synthetic Benchmark {run_id[:8]}"},
        )
        for start in range(0, size, batch_size):
            stop = min(start + batch_size, size)
            audio_files = [
                AudioFile(
                    checksum=hashlib.sha256(f"{run_id}:{index}".encode()).hexdigest(),
                    storage_backend="benchmark",
                    object_key=f"benchmark/{run_id}/{index}.mp3",
                    original_filename=f"synthetic-{index}.mp3",
                    size_bytes=1,
                    duration_ms=180_000,
                )
                for index in range(start, stop)
            ]
            with transaction.atomic():
                AudioFile.objects.bulk_create(audio_files, batch_size=batch_size)
                Track.objects.bulk_create(
                    [
                        Track(
                            title=f"Synthetic Track {start + offset:06d}",
                            artist=artist,
                            audio_file=audio_file,
                            genres=["benchmark"],
                        )
                        for offset, audio_file in enumerate(audio_files)
                    ],
                    batch_size=batch_size,
                )
            self.stdout.write(f"generated={stop}/{size}")
