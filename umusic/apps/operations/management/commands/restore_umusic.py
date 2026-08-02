import json
from pathlib import Path

from django.core.management import call_command
from django.core.management.base import BaseCommand, CommandError, CommandParser

from umusic.apps.library.storage import get_storage_for_backend


class Command(BaseCommand):
    help = "Restore a uMusic fixture and verify every referenced media object."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("--input", required=True)
        parser.add_argument("--confirm", action="store_true")

    def handle(self, *args: object, **options: object) -> None:
        if not options["confirm"]:
            raise CommandError("Restore requires --confirm")
        source = Path(str(options["input"])).resolve()
        call_command("loaddata", str(source / "database.json"))
        manifest = json.loads((source / "media-manifest.json").read_text())
        missing = [
            item["object_key"]
            for item in manifest
            if not get_storage_for_backend(item["storage_backend"]).exists(item["object_key"])
        ]
        if missing:
            raise CommandError(f"Restore has {len(missing)} missing media objects")
        self.stdout.write(
            self.style.SUCCESS(f"Restored and verified {len(manifest)} media objects")
        )
