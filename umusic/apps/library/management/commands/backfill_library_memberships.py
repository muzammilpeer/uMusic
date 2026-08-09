from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from umusic.apps.library.models import LibraryMembership, Track


class Command(BaseCommand):
    help = "Backfill existing catalog tracks into one owner's private library."

    def add_arguments(self, parser):  # type: ignore[no-untyped-def]
        parser.add_argument("--username", required=True)
        parser.add_argument("--apply", action="store_true")

    def handle(self, *args, **options):  # type: ignore[no-untyped-def]
        user_model = get_user_model()
        try:
            owner = user_model.objects.get(username=options["username"])
        except user_model.DoesNotExist as exc:
            raise CommandError("The requested owner does not exist.") from exc

        track_ids = list(Track.objects.filter(is_active=True).values_list("id", flat=True))
        existing = set(
            LibraryMembership.objects.filter(owner=owner, track_id__in=track_ids)
            .values_list("track_id", flat=True)
        )
        missing = [track_id for track_id in track_ids if track_id not in existing]
        mode = "APPLY" if options["apply"] else "DRY RUN"
        self.stdout.write(
            f"{mode}: owner={owner.username} active_tracks={len(track_ids)} "
            f"existing={len(existing)} missing={len(missing)}"
        )
        if not options["apply"] or not missing:
            return
        with transaction.atomic():
            LibraryMembership.objects.bulk_create(
                [
                    LibraryMembership(
                        owner=owner,
                        track_id=track_id,
                        source=LibraryMembership.Source.BACKFILL,
                    )
                    for track_id in missing
                ],
                ignore_conflicts=True,
            )
        self.stdout.write(self.style.SUCCESS(f"Created {len(missing)} memberships."))
