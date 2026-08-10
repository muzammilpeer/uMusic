from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("imports", "0002_alter_adapterjob_adapter_alter_adapterjob_status_and_more")]
    operations = [
        migrations.AddField(
            model_name="adapterjob",
            name="idempotency_key",
            field=models.UUIDField(blank=True, null=True),
        ),
        migrations.AddConstraint(
            model_name="adapterjob",
            constraint=models.UniqueConstraint(
                condition=models.Q(idempotency_key__isnull=False),
                fields=("owner", "idempotency_key"),
                name="import_job_owner_idempotency_key",
            ),
        ),
    ]
