from django.contrib import admin

from umusic.apps.library.models import (
    Album,
    Artist,
    Artwork,
    AudioFile,
    AuditEvent,
    ImportJob,
    LibraryMembership,
    Track,
    TrackAnalysis,
)

admin.site.register(
    [Artist, Album, Artwork, AudioFile, Track, TrackAnalysis, LibraryMembership, ImportJob, AuditEvent]
)
