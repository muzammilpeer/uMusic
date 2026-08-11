import time

from django.core.management.base import BaseCommand

from umusic.apps.library.metadata_enrichment import enrich_track
from umusic.apps.library.models import Track


class Command(BaseCommand):
    help = "Enrich MP3 catalog metadata from MusicBrainz using confidence-gated filename matching."

    def add_arguments(self, parser):
        parser.add_argument("--track-id")
        parser.add_argument("--all", action="store_true")
        parser.add_argument("--threshold", type=int, default=95)

    def handle(self, *args, **options):
        if not options["all"] and not options["track_id"]:
            self.stderr.write("Choose --all or --track-id <uuid>.")
            return
        tracks = Track.objects.filter(is_active=True).select_related("artist", "audio_file")
        if options["track_id"]:
            tracks = tracks.filter(id=options["track_id"])
        total = matched = applied = failed = 0
        for track in tracks.iterator():
            if total:
                time.sleep(1.05)
            total += 1
            try:
                result = enrich_track(
                    track, apply_threshold=max(0, min(options["threshold"], 100))
                )
            except Exception as error:
                failed += 1
                self.stderr.write(f"{track.id} lookup_failed={type(error).__name__}")
                continue
            matched += int(result.matched)
            applied += int(result.applied)
            self.stdout.write(f"{track.id} score={result.score} applied={result.applied}")
        self.stdout.write(
            self.style.SUCCESS(
                f"checked={total} matched={matched} applied={applied} failed={failed}"
            )
        )
