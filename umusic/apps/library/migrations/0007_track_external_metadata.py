from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("library", "0006_trackanalysis")]

    operations = [
        migrations.AddField(
            model_name="track",
            name="external_metadata",
            field=models.JSONField(blank=True, default=dict),
        ),
    ]
