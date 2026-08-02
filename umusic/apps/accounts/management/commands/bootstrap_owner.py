import os
from argparse import ArgumentParser

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = "Create the initial uMusic owner from arguments or environment variables."

    def add_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("--username", default=os.getenv("UMUSIC_OWNER_USERNAME"))
        parser.add_argument("--email", default=os.getenv("UMUSIC_OWNER_EMAIL", ""))
        parser.add_argument("--password", default=os.getenv("UMUSIC_OWNER_PASSWORD"))

    def handle(self, *args: object, **options: object) -> None:
        username = options.get("username")
        password = options.get("password")
        email = options.get("email", "")
        if not isinstance(username, str) or not username:
            raise CommandError("Provide --username or UMUSIC_OWNER_USERNAME.")
        if not isinstance(password, str) or len(password) < 12:
            raise CommandError("Provide a password of at least 12 characters.")

        user_model = get_user_model()
        user, created = user_model.objects.get_or_create(
            username=username,
            defaults={"email": email, "is_staff": True, "is_superuser": True},
        )
        if created:
            user.set_password(password)
            user.save(update_fields=["password"])
            self.stdout.write(self.style.SUCCESS(f"Created owner {username}."))
        else:
            self.stdout.write(f"Owner {username} already exists; no changes made.")
