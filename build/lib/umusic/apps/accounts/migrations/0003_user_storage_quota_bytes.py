from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("accounts", "0002_device")]

    operations = [
        migrations.AddField(
            model_name="user",
            name="storage_quota_bytes",
            field=models.PositiveBigIntegerField(default=5 * 1024 * 1024 * 1024),
        )
    ]
