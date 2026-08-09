import json
from pathlib import Path

from django.core.management import call_command
from django.core.management.base import BaseCommand, CommandError, CommandParser

from umusic.apps.library.models import AudioFile, LibraryMembership
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
        membership_audio_ids = set(
            LibraryMembership.objects.filter(state=LibraryMembership.State.ACTIVE)
            .values_list("track__audio_file_id", flat=True)
        )
        required_audio_ids = membership_audio_ids or set(
            AudioFile.objects.filter(track__is_active=True).values_list("id", flat=True)
        )
        required_ids = {str(value) for value in required_audio_ids}
        missing = [
            item["object_key"]
            for item in manifest
            if item["id"] in required_ids
            if not get_storage_for_backend(item["storage_backend"]).exists(item["object_key"])
        ]
        if missing:
            raise CommandError(f"Restore has {len(missing)} missing active media objects")
        archived_missing = sum(
            1
            for item in manifest
            if item["id"] not in required_ids
            and not get_storage_for_backend(item["storage_backend"]).exists(item["object_key"])
        )
        self.stdout.write(
            self.style.SUCCESS(
                f"Restored {len(manifest)} media references; all active media verified; "
                f"{archived_missing} inactive tombstone(s) have no stored object"
            )
        )
