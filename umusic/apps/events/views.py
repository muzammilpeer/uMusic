from django.db import IntegrityError, transaction
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from umusic.apps.contexts.models import ContextSnapshot
from umusic.apps.events.models import ListeningEvent
from umusic.apps.events.serializers import (
    ListeningEventInputSerializer,
    ListeningEventOutputSerializer,
)
from umusic.apps.events.services import event_defaults, rebuild_play_facts
from umusic.apps.library.models import Track
from umusic.apps.playback.models import PlaybackSession

MAX_BATCH_SIZE = 500


class EventBatchView(APIView):
    def post(self, request: Request) -> Response:
        payload = request.data.get("events") if isinstance(request.data, dict) else None
        if not isinstance(payload, list) or not payload:
            return Response({"error": "events must be a non-empty list"}, status=400)
        if len(payload) > MAX_BATCH_SIZE:
            return Response(
                {"error": f"A batch may contain at most {MAX_BATCH_SIZE} events"}, status=400
            )
        serializer = ListeningEventInputSerializer(data=payload, many=True)
        serializer.is_valid(raise_exception=True)
        validated = serializer.validated_data
        track_ids = {item["track_id"] for item in validated}
        if Track.objects.filter(id__in=track_ids, is_active=True).count() != len(track_ids):
            return Response({"error": "One or more tracks were not found"}, status=400)
        session_ids = {item.get("playback_session_id") for item in validated} - {None}
        owned_sessions = PlaybackSession.objects.filter(
            id__in=session_ids, owner=request.user
        ).count()
        if owned_sessions != len(session_ids):
            return Response({"error": "One or more playback sessions were not found"}, status=400)
        context_ids = {item.get("context_snapshot_id") for item in validated} - {None}
        owned_contexts = ContextSnapshot.objects.filter(
            id__in=context_ids, owner=request.user
        ).count()
        if owned_contexts != len(context_ids):
            return Response({"error": "One or more context snapshots were not found"}, status=400)

        accepted = 0
        duplicate = 0
        event_ids: list[str] = []
        for item in validated:
            try:
                with transaction.atomic():
                    event, created = ListeningEvent.objects.get_or_create(
                        owner=request.user,
                        client_event_id=item["client_event_id"],
                        defaults=event_defaults(item),
                    )
            except IntegrityError:
                event = ListeningEvent.objects.get(
                    owner=request.user, client_event_id=item["client_event_id"]
                )
                created = False
            accepted += int(created)
            duplicate += int(not created)
            event_ids.append(str(event.id))
        rebuild_play_facts(request.user)
        return Response(
            {
                "accepted": accepted,
                "duplicates": duplicate,
                "event_ids": event_ids,
            },
            status=202,
        )


class EventListView(APIView):
    def get(self, request: Request) -> Response:
        events = ListeningEvent.objects.filter(owner=request.user).order_by("-received_at")[:200]
        return Response(ListeningEventOutputSerializer(events, many=True).data)
