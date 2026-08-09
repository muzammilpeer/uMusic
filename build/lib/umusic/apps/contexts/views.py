from django.db.models import Q
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from umusic.apps.accounts.models import User
from umusic.apps.contexts.models import Activity, Geofence
from umusic.apps.contexts.serializers import (
    ActivitySerializer,
    ContextSnapshotInputSerializer,
    ContextSnapshotSerializer,
    GeofenceSerializer,
)
from umusic.apps.contexts.services import create_snapshot, delete_place, forget_place_learning


class ActivityCollectionView(APIView):
    def get(self, request: Request) -> Response:
        activities = Activity.objects.filter(Q(owner=request.user) | Q(owner__isnull=True))
        return Response(ActivitySerializer(activities, many=True).data)

    def post(self, request: Request) -> Response:
        serializer = ActivitySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        activity = serializer.save(owner=request.user, is_preset=False, kind=Activity.Kind.CUSTOM)
        return Response(ActivitySerializer(activity).data, status=201)


class GeofenceCollectionView(APIView):
    def get(self, request: Request) -> Response:
        places = Geofence.objects.filter(owner=request.user)
        return Response(GeofenceSerializer(places, many=True).data)

    def post(self, request: Request) -> Response:
        serializer = GeofenceSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        place = serializer.save(owner=request.user)
        return Response(GeofenceSerializer(place).data, status=201)


class GeofenceDetailView(APIView):
    def get_object(self, request: Request, place_id: str) -> Geofence | None:
        return Geofence.objects.filter(id=place_id, owner=request.user).first()

    def get(self, request: Request, place_id: str) -> Response:
        place = self.get_object(request, place_id)
        return Response(GeofenceSerializer(place).data) if place else Response(status=404)

    def patch(self, request: Request, place_id: str) -> Response:
        place = self.get_object(request, place_id)
        if place is None:
            return Response(status=404)
        serializer = GeofenceSerializer(place, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        return Response(GeofenceSerializer(serializer.save()).data)

    def delete(self, request: Request, place_id: str) -> Response:
        place = self.get_object(request, place_id)
        if place is None:
            return Response(status=404)
        owner = request.user
        assert isinstance(owner, User)
        delete_place(owner, place)
        return Response(status=204)


class ForgetPlaceView(APIView):
    def post(self, request: Request, place_id: str) -> Response:
        place = Geofence.objects.filter(id=place_id, owner=request.user).first()
        if place is None:
            return Response(status=404)
        owner = request.user
        assert isinstance(owner, User)
        record = forget_place_learning(owner, place)
        return Response({"forgotten_at": record.forgotten_at}, status=201)


class ContextSnapshotView(APIView):
    def post(self, request: Request) -> Response:
        serializer = ContextSnapshotInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        owner = request.user
        assert isinstance(owner, User)
        try:
            snapshot = create_snapshot(owner, serializer.validated_data)
        except ValueError as error:
            return Response({"error": str(error)}, status=404)
        return Response(ContextSnapshotSerializer(snapshot).data, status=201)
