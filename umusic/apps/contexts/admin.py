from django.contrib import admin

from umusic.apps.contexts.models import Activity, ContextForgetRecord, ContextSnapshot, Geofence

admin.site.register([Activity, Geofence, ContextSnapshot, ContextForgetRecord])
