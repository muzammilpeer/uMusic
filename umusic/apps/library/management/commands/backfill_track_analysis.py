from django.core.management.base import BaseCommand
from django.db.models import F, Q

from umusic.apps.library.models import Track
from umusic.apps.library.tasks import analyze_track_audio


class Command(BaseCommand):
    help = "Queue versioned track analysis without reading media in the web process."

    def add_arguments(self, parser):
        parser.add_argument("--limit", type=int, default=100)
        parser.add_argument("--track-id", action="append", default=[])
        parser.add_argument("--dry-run", action="store_true")
        parser.add_argument("--force", action="store_true")

    def handle(self, *args, **options):
        queryset = Track.objects.filter(is_active=True).order_by("id")
        if options["track_id"]:
            queryset = queryset.filter(id__in=options["track_id"])
        if not options["force"]:
            queryset = queryset.filter(
                Q(analysis__isnull=True)
                | ~Q(analysis__status="succeeded")
                | ~Q(analysis__source_checksum=F("audio_file__checksum"))
            )
        track_ids = list(queryset.values_list("id", flat=True)[: max(0, options["limit"])])
        if not options["dry_run"]:
            for track_id in track_ids:
                analyze_track_audio.apply_async(args=[str(track_id)], queue="audio_analysis")
        self.stdout.write(f"{'Would queue' if options['dry_run'] else 'Queued'} {len(track_ids)} track(s).")
