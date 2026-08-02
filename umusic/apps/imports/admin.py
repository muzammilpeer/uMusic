from django.contrib import admin

from umusic.apps.imports.models import AdapterJob, RemoteImportItem, TasteCandidate

admin.site.register([AdapterJob, RemoteImportItem, TasteCandidate])
