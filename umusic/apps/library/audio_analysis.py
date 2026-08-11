import hashlib
import math
import struct
from dataclasses import dataclass
from typing import Protocol

from django.db import transaction
from django.utils import timezone

from umusic.apps.library.models import Track, TrackAnalysis


@dataclass(frozen=True)
class AnalysisResult:
    provider: str
    model_version: str
    scalars: dict[str, float]
    embedding: tuple[float, ...]


class AudioAnalysisProvider(Protocol):
    name: str
    version: str

    def analyze_track(self, track: Track) -> AnalysisResult: ...


class DeterministicAnalysisProvider:
    """Test/development provider proving the pipeline without inspecting private audio."""

    name = "deterministic"
    version = "checksum-fixture-1"

    def analyze(self, source_checksum: str) -> AnalysisResult:
        values = []
        seed = bytes.fromhex(source_checksum)
        counter = 0
        while len(values) < 64:
            digest = hashlib.sha256(seed + counter.to_bytes(2, "big")).digest()
            values.extend((byte / 127.5) - 1 for byte in digest)
            counter += 1
        vector = values[:64]
        norm = math.sqrt(sum(value * value for value in vector)) or 1
        embedding = tuple(value / norm for value in vector)
        return AnalysisResult(
            provider=self.name,
            model_version=self.version,
            scalars={"energy": round((seed[0] / 255), 6)},
            embedding=embedding,
        )

    def analyze_track(self, track: Track) -> AnalysisResult:
        return self.analyze(track.audio_file.checksum.lower())


def analyze_track(track_id: object, provider: AudioAnalysisProvider | None = None) -> TrackAnalysis:
    provider = provider or DeterministicAnalysisProvider()
    track = Track.objects.select_related("audio_file").get(pk=track_id)
    checksum = track.audio_file.checksum.lower()
    result = provider.analyze_track(track)
    payload = b"".join(struct.pack("<e", value) for value in result.embedding)
    with transaction.atomic():
        analysis, _ = TrackAnalysis.objects.select_for_update().get_or_create(
            track=track,
            defaults={"source_checksum": checksum, "provider": result.provider, "model_version": result.model_version},
        )
        analysis.source_checksum = checksum
        analysis.provider = result.provider
        analysis.model_version = result.model_version
        analysis.feature_schema_version = 1
        analysis.status = TrackAnalysis.Status.SUCCEEDED
        analysis.attempt_count += 1
        analysis.scalar_features = result.scalars
        analysis.embedding_dimension = len(result.embedding)
        analysis.embedding_encoding = "float16_le"
        analysis.embedding = payload
        analysis.error_code = ""
        analysis.completed_at = timezone.now()
        analysis.save()
        track.save(update_fields=["updated_at"])
    return analysis
