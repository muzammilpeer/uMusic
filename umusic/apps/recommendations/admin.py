from django.contrib import admin

from umusic.apps.recommendations.models import Affinity, LearningConfiguration, LearningRun

admin.site.register([LearningConfiguration, Affinity, LearningRun])
