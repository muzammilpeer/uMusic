from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from umusic.apps.accounts.models import User
from umusic.apps.imports.adapter_services import (
    confirm_candidate,
    import_folder,
    import_taste,
    import_youtube,
)
from umusic.apps.imports.adapters import enabled_adapters
from umusic.apps.imports.models import AdapterJob, TasteCandidate
from umusic.apps.imports.remote_services import create_remote_import


def _job(job: AdapterJob) -> dict[str, object]:
    return {
        "id": str(job.id),
        "adapter": job.adapter,
        "status": job.status,
        "imported_count": job.imported_count,
        "error": job.error,
        "operator_attested": job.operator_attested,
        "provenance": job.provenance,
        "items": [
            {
                "id": str(item.id),
                "position": item.position,
                "kind": item.kind,
                "source_host": item.source_host,
                "status": item.status,
                "imported": item.imported,
                "error": item.error,
            }
            for item in job.remote_items.all()
        ],
    }


class AdapterListView(APIView):
    def get(self, request: Request) -> Response:
        return Response({"enabled": sorted(enabled_adapters())})


class FolderImportView(APIView):
    def post(self, request: Request) -> Response:
        if "folder" not in enabled_adapters():
            return Response(status=404)
        owner = request.user
        assert isinstance(owner, User)
        try:
            job = import_folder(owner, str(request.data.get("folder", "")))
        except (ValueError, PermissionError) as error:
            return Response({"error": str(error)}, status=400)
        return Response(_job(job), status=201)


class TasteImportView(APIView):
    def post(self, request: Request) -> Response:
        if "taste" not in enabled_adapters():
            return Response(status=404)
        entries = request.data.get("entries")
        if not isinstance(entries, list) or not entries:
            return Response({"error": "entries must be a non-empty list"}, status=400)
        owner = request.user
        assert isinstance(owner, User)
        job = import_taste(owner, entries[:1000])
        candidates = [
            {
                "id": str(item.id),
                "artist": item.artist,
                "title": item.title,
                "state": item.state,
                "confidence": item.confidence,
                "matched_track_id": str(item.matched_track_id or ""),
            }
            for item in job.candidates.all()
        ]
        return Response({**_job(job), "candidates": candidates}, status=201)


class ConfirmCandidateView(APIView):
    def post(self, request: Request, candidate_id: str) -> Response:
        candidate = TasteCandidate.objects.filter(id=candidate_id, job__owner=request.user).first()
        if candidate is None:
            return Response(status=404)
        owner = request.user
        assert isinstance(owner, User)
        try:
            confirm_candidate(owner, candidate, bool(request.data.get("accept")))
        except ValueError as error:
            return Response({"error": str(error)}, status=400)
        return Response({"id": str(candidate.id), "state": candidate.state})


class YouTubeImportView(APIView):
    def post(self, request: Request) -> Response:
        if "youtube" not in enabled_adapters():
            return Response(status=404)
        owner = request.user
        assert isinstance(owner, User)
        try:
            job = import_youtube(
                owner, str(request.data.get("url", "")), request.data.get("attested") is True
            )
        except (ValueError, PermissionError, RuntimeError) as error:
            return Response({"error": str(error)}, status=400)
        return Response(_job(job), status=201)


class RemoteImportView(APIView):
    def post(self, request: Request) -> Response:
        owner = request.user
        assert isinstance(owner, User)
        try:
            job = create_remote_import(
                owner,
                str(request.data.get("urls", "")),
                request.data.get("attested") is True,
            )
        except (ValueError, PermissionError) as error:
            return Response({"error": str(error)}, status=400)
        return Response(_job(job), status=202)


class AdapterJobDetailView(APIView):
    def get(self, request: Request, job_id: str) -> Response:
        job = AdapterJob.objects.filter(id=job_id, owner=request.user).first()
        return Response(_job(job)) if job else Response(status=404)
