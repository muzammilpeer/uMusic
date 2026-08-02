import json
from pathlib import Path

from django.core.management import call_command
from django.core.management.base import BaseCommand, CommandParser

from umusic.apps.library.models import AudioFile


class Command(BaseCommand):
    help = "Create a database fixture and checksum media-reference manifest."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("--output", required=True)

    def handle(self, *args: object, **options: object) -> None:
        target = Path(str(options["output"])).resolve()
        target.mkdir(parents=True, exist_ok=True)
        with (target / "database.json").open("w") as output:
            call_command(
                "dumpdata",
                "--natural-foreign",
                "--natural-primary",
                "--exclude",
                "contenttypes",
                "--exclude",
                "auth.permission",
                "--exclude",
                "sessions",
                stdout=output,
            )
        manifest = list(
            AudioFile.objects.values(
                "id", "checksum", "storage_backend", "object_key", "size_bytes"
            )
        )
        (target / "media-manifest.json").write_text(json.dumps(manifest, indent=2, default=str))
        self.stdout.write(self.style.SUCCESS(f"Backup created at {target}"))
