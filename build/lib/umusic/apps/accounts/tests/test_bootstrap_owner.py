import pytest
from django.core.management import CommandError, call_command

from umusic.apps.accounts.models import User

pytestmark = pytest.mark.django_db


def test_bootstrap_owner_creates_superuser_and_is_idempotent() -> None:
    call_command(
        "bootstrap_owner",
        username="owner",
        email="owner@example.test",
        password="long-test-password",
    )
    call_command(
        "bootstrap_owner",
        username="owner",
        email="ignored@example.test",
        password="another-long-password",
    )

    owner = User.objects.get(username="owner")
    assert owner.email == "owner@example.test"
    assert owner.is_staff and owner.is_superuser
    assert owner.check_password("long-test-password")


def test_bootstrap_owner_rejects_short_password() -> None:
    with pytest.raises(CommandError, match="at least 12"):
        call_command("bootstrap_owner", username="owner", password="short")
