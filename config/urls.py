import uuid

from django.contrib import admin
from django.urls import include, path, register_converter
from django.views.generic import RedirectView


class CaseInsensitiveUUIDConverter:
    regex = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"

    def to_python(self, value: str) -> uuid.UUID:
        return uuid.UUID(value)

    def to_url(self, value: object) -> str:
        return str(value).lower()


# Swift's UUID string representation is uppercase. Accept both cases at the API
# boundary while new clients normalize path segments to lowercase.
register_converter(CaseInsensitiveUUIDConverter, "uuid")

urlpatterns = [
    path("", RedirectView.as_view(pattern_name="library:index", permanent=False)),
    path("admin/", admin.site.urls),
    path("accounts/", include("django.contrib.auth.urls")),
    path("api/v1/", include("umusic.apps.accounts.api_urls")),
    path("api/v1/", include("umusic.apps.sync.urls")),
    path("api/v1/", include("umusic.apps.library.api_urls")),
    path("library/", include("umusic.apps.library.urls")),
    path("api/v1/imports/", include("umusic.apps.imports.urls")),
    path("api/v1/adapters/", include("umusic.apps.imports.adapter_urls")),
    path("api/v1/tracks/", include("umusic.apps.playback.stream_urls")),
    path("api/v1/playback/", include("umusic.apps.playback.urls")),
    path("api/v1/playlists/", include("umusic.apps.playlists.urls")),
    path("api/v1/events/", include("umusic.apps.events.urls")),
    path("api/v1/contexts/", include("umusic.apps.contexts.urls")),
    path("api/v1/learning/", include("umusic.apps.recommendations.urls")),
    path("api/v1/recommendations/", include("umusic.apps.recommendations.generation_urls")),
    path("health/", include("umusic.apps.operations.urls")),
]
