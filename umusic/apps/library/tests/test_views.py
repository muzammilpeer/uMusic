import pytest
from django.test import Client

from umusic.apps.accounts.models import User
from umusic.apps.library.models import ImportJob

pytestmark = pytest.mark.django_db


def test_library_redirects_anonymous_user_to_login() -> None:
    response = Client().get("/library/")

    assert response.status_code == 302
    assert response.headers["Location"].startswith("/accounts/login/")


def test_import_detail_is_owner_scoped() -> None:
    owner = User.objects.create_user(username="owner")
    other = User.objects.create_user(username="other")
    job = ImportJob.objects.create(owner=owner, source_filename="private.mp3")
    client = Client()
    client.force_login(other)

    assert client.get(f"/library/imports/{job.id}/").status_code == 404


def test_authenticated_library_and_import_list_render() -> None:
    owner = User.objects.create_user(username="owner")
    ImportJob.objects.create(owner=owner, source_filename="pending.mp3")
    client = Client()
    client.force_login(owner)

    library_response = client.get("/library/")
    imports_response = client.get("/library/imports/")

    assert library_response.status_code == 200
    assert b"Music library" in library_response.content
    assert imports_response.status_code == 200
    assert b"pending.mp3" in imports_response.content
