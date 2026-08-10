from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("library", "0004_librarymembership")]
    operations = [
        migrations.AddField(
            model_name="track",
            name="content_classifications",
            field=models.JSONField(blank=True, default=list),
        ),
    ]
