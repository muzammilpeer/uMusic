from django.contrib import admin

from umusic.apps.library.models import (
    Album,
    Artist,
    Artwork,
    AudioFile,
    AuditEvent,
    ImportJob,
    Track,
)

admin.site.register([Artist, Album, Artwork, AudioFile, Track, ImportJob, AuditEvent])
