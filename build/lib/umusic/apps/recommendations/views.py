from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from umusic.apps.accounts.models import User
from umusic.apps.recommendations.models import Affinity
from umusic.apps.recommendations.serializers import AffinitySerializer, LearningRunSerializer
from umusic.apps.recommendations.services import rebuild_affinities, reset_learning


class AffinityListView(APIView):
    def get(self, request: Request) -> Response:
        affinities = Affinity.objects.filter(owner=request.user).select_related("configuration")
        for field in ("target_type", "context_type", "context_key"):
            value = request.query_params.get(field)
            if value:
                affinities = affinities.filter(**{field: value})
        return Response(AffinitySerializer(affinities[:500], many=True).data)


class RebuildLearningView(APIView):
    def post(self, request: Request) -> Response:
        owner = request.user
        assert isinstance(owner, User)
        run = rebuild_affinities(owner)
        return Response(LearningRunSerializer(run).data, status=201)


class ResetLearningView(APIView):
    def post(self, request: Request) -> Response:
        owner = request.user
        assert isinstance(owner, User)
        return Response({"deleted": reset_learning(owner)})
