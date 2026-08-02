from django.core.management.base import BaseCommand

from umusic.apps.events.services import rebuild_play_facts


class Command(BaseCommand):
    help = "Rebuild all derived play facts from the append-only listening event log."

    def handle(self, *args: object, **options: object) -> None:
        count = rebuild_play_facts()
        self.stdout.write(self.style.SUCCESS(f"Rebuilt {count} play facts."))
