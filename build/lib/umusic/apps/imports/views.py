from pathlib import Path

from django.conf import settings
from django.db import transaction
from rest_framework import status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from umusic.apps.imports.serializers import ImportJobSerializer
from umusic.apps.library.models import ImportJob
from umusic.apps.library.services import process_import, quarantine_upload


class UploadView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request: Request) -> Response:
        uploads = request.FILES.getlist("files") or request.FILES.getlist("file")
        if not uploads:
            return Response(
                {"error": {"code": "NO_FILES", "message": "Select at least one MP3 file."}},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if len(uploads) > settings.UMUSIC_MAX_UPLOAD_FILES:
            return Response(
                {
                    "error": {
                        "code": "TOO_MANY_FILES",
                        "message": (
                            f"Upload at most {settings.UMUSIC_MAX_UPLOAD_FILES} files per batch."
                        ),
                    }
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        is_batch = "files" in request.FILES
        if not is_batch and Path(uploads[0].name or "").suffix.casefold() != ".mp3":
            return Response(
                {
                    "error": {
                        "code": "INVALID_EXTENSION",
                        "message": "Only MP3 files are accepted.",
                    }
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        jobs: list[ImportJob] = []
        for upload in uploads:
            upload_name = upload.name or "upload"
            if Path(upload_name).suffix.casefold() != ".mp3":
                job = ImportJob.objects.create(
                    owner=request.user,
                    status=ImportJob.Status.FAILED,
                    source_filename=Path(upload_name).name[:255],
                    size_bytes=upload.size or 0,
                    error_code="INVALID_EXTENSION",
                    error_message="Only MP3 files are accepted.",
                )
            else:
                with transaction.atomic():
                    job = quarantine_upload(upload, request.user)
                if job.status == ImportJob.Status.PENDING:
                    job = process_import(job)
            jobs.append(job)

        successful = sum(
            job.status in {ImportJob.Status.COMPLETED, ImportJob.Status.DUPLICATE} for job in jobs
        )
        if len(jobs) == 1 and not is_batch:
            response_status = status.HTTP_201_CREATED if successful else status.HTTP_400_BAD_REQUEST
            return Response(ImportJobSerializer(jobs[0]).data, status=response_status)

        response_status = (
            status.HTTP_201_CREATED
            if successful == len(jobs)
            else status.HTTP_207_MULTI_STATUS
            if successful
            else status.HTTP_400_BAD_REQUEST
        )
        return Response(
            {
                "summary": {
                    "total": len(jobs),
                    "successful": successful,
                    "failed": len(jobs) - successful,
                },
                "jobs": ImportJobSerializer(jobs, many=True).data,
            },
            status=response_status,
        )


class ImportJobView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request: Request, job_id: str) -> Response:
        job = ImportJob.objects.filter(id=job_id, owner=request.user).first()
        if job is None:
            return Response(
                {"error": {"code": "NOT_FOUND", "message": "Import job not found."}},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response(ImportJobSerializer(job).data)
