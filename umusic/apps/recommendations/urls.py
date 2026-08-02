from django.urls import path

from umusic.apps.recommendations.views import (
    AffinityListView,
    RebuildLearningView,
    ResetLearningView,
)

urlpatterns = [
    path("affinities/", AffinityListView.as_view(), name="api-learning-affinities"),
    path("rebuild/", RebuildLearningView.as_view(), name="api-learning-rebuild"),
    path("reset/", ResetLearningView.as_view(), name="api-learning-reset"),
]
