from typing import Any

from django.contrib import admin
from django.http import HttpRequest

from umusic.apps.events.models import ListeningEvent, PlayFact


@admin.register(ListeningEvent)
class ListeningEventAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("event_type", "track", "owner", "position_ms", "client_timestamp", "offline")
    list_filter = ("event_type", "offline")
    search_fields = ("track__title", "track__artist__name", "client_event_id", "playback_id")
    readonly_fields = [field.name for field in ListeningEvent._meta.fields]

    def has_add_permission(self, request: HttpRequest) -> bool:
        return False

    def has_change_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False


@admin.register(PlayFact)
class PlayFactAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("track", "owner", "listening_ms", "completed", "early_skip", "replayed")
    list_filter = ("completed", "early_skip", "replayed", "explicit_feedback")
