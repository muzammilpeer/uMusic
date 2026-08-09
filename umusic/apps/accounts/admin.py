from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from umusic.apps.accounts.models import Device, User
from umusic.apps.library.models import AuditEvent


@admin.register(User)
class UMusicUserAdmin(UserAdmin):  # type: ignore[type-arg]
    list_display = (
        "username", "email", "first_name", "last_name", "is_staff", "is_active",
        "storage_quota_bytes",
    )
    fieldsets = (  # type: ignore[misc]
        *UserAdmin.fieldsets,
        ("uMusic", {"fields": ("storage_quota_bytes",)}),
    )
    add_fieldsets = (
        *UserAdmin.add_fieldsets,
        ("uMusic", {"fields": ("storage_quota_bytes",)}),
    )

    def save_model(self, request, obj, form, change):  # type: ignore[no-untyped-def]
        super().save_model(request, obj, form, change)
        sensitive = sorted(
            field
            for field in form.changed_data
            if field in {"is_active", "password", "storage_quota_bytes"}
        )
        if sensitive or not change:
            AuditEvent.objects.create(
                actor=request.user,
                action="account.user.updated" if change else "account.user.created",
                target_type="user",
                target_id=str(obj.id),
                metadata={"changed_fields": sensitive},
            )


admin.site.register(Device)
