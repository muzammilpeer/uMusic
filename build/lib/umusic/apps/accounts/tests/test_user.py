import pytest
from django.contrib.auth import get_user_model


@pytest.mark.django_db
def test_custom_user_model_is_active_by_default() -> None:
    user = get_user_model().objects.create_user(username="listener", password="test-password")

    assert user.is_active is True
    assert user.check_password("test-password")
