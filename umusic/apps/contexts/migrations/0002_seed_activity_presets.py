from django.db import migrations


PRESETS = [
    ("cycling", "Cycling", ["warmup", "sustain", "recovery", "cooldown"]),
    ("running", "Running", ["warmup", "sustain", "cooldown"]),
    ("gym", "Gym", ["warmup", "sustain", "rest", "cooldown"]),
    ("focus", "Focus", ["steady"]),
    ("walking", "Walking", ["warmup", "steady", "cooldown"]),
    ("relax", "Relax", ["steady"]),
    ("commute", "Commute", ["steady"]),
]


def seed_presets(apps, schema_editor):
    Activity = apps.get_model("contexts", "Activity")
    for slug, name, phases in PRESETS:
        Activity.objects.get_or_create(
            owner=None,
            slug=slug,
            defaults={
                "name": name,
                "kind": slug,
                "phase_curve": phases,
                "is_preset": True,
            },
        )


def remove_presets(apps, schema_editor):
    Activity = apps.get_model("contexts", "Activity")
    Activity.objects.filter(owner=None, is_preset=True).delete()


class Migration(migrations.Migration):
    dependencies = [("contexts", "0001_initial")]
    operations = [migrations.RunPython(seed_presets, remove_presets)]
