import math
import os
import subprocess
import tempfile
from functools import lru_cache
from pathlib import Path

from django.conf import settings

from umusic.apps.library.audio_analysis import AnalysisResult
from umusic.apps.library.models import Track
from umusic.apps.library.storage import get_storage_for_backend


class MERTAnalysisProvider:
    name = "mert"

    def __init__(self) -> None:
        self.model_id = settings.UMUSIC_MERT_MODEL_ID
        self.revision = settings.UMUSIC_MERT_MODEL_REVISION
        self.version = f"{self.model_id}@{self.revision}:mean-last-rp64-v1"
        self._model = None
        self._processor = None

    def _load(self):
        if self._model is None:
            import torch
            from transformers import AutoModel, Wav2Vec2FeatureExtractor

            self._processor = Wav2Vec2FeatureExtractor.from_pretrained(
                self.model_id, revision=self.revision, cache_dir=settings.UMUSIC_MERT_CACHE,
                local_files_only=settings.UMUSIC_MERT_LOCAL_FILES_ONLY,
            )
            self._model = AutoModel.from_pretrained(
                self.model_id, revision=self.revision, cache_dir=settings.UMUSIC_MERT_CACHE,
                local_files_only=settings.UMUSIC_MERT_LOCAL_FILES_ONLY,
                trust_remote_code=True,
            ).eval()
            self._model.to("cpu")
            torch.set_num_threads(max(1, settings.UMUSIC_MERT_CPU_THREADS))
        return self._model, self._processor

    def analyze_track(self, track: Track) -> AnalysisResult:
        if track.audio_file.size_bytes > settings.UMUSIC_MERT_MAX_AUDIO_BYTES:
            raise ValueError("audio_too_large")
        storage = get_storage_for_backend(track.audio_file.storage_backend)
        with tempfile.TemporaryDirectory(prefix="umusic-analysis-") as directory:
            source = Path(directory) / "source.mp3"
            with storage.open(track.audio_file.object_key) as incoming, source.open("wb") as output:
                while chunk := incoming.read(1024 * 1024):
                    output.write(chunk)
            excerpts = self._decode_excerpts(source, track.audio_file.duration_ms)
        embedding = self._embed(excerpts)
        energy = self._energy(excerpts)
        return AnalysisResult(
            provider=self.name,
            model_version=self.version,
            scalars={"energy": round(energy, 6)},
            embedding=tuple(embedding),
        )

    def _decode_excerpts(self, source: Path, duration_ms: int) -> list[list[float]]:
        duration = max(duration_ms / 1000, 0)
        length = min(settings.UMUSIC_MERT_EXCERPT_SECONDS, max(duration, 1))
        starts = sorted({0.0, max((duration - length) / 2, 0), max(duration - length, 0)})
        excerpts = []
        for start in starts:
            command = [
                settings.UMUSIC_FFMPEG_PATH, "-v", "error", "-ss", f"{start:.3f}",
                "-i", str(source), "-t", f"{length:.3f}", "-ac", "1", "-ar", "24000",
                "-f", "f32le", "pipe:1",
            ]
            completed = subprocess.run(command, capture_output=True, check=True, timeout=60)
            import numpy as np

            samples = np.frombuffer(completed.stdout, dtype="<f4")
            if samples.size < 2400:
                raise ValueError("audio_decode_empty")
            excerpts.append(samples.tolist())
        return excerpts

    def _embed(self, excerpts: list[list[float]]) -> list[float]:
        import numpy as np
        import torch

        model, processor = self._load()
        vectors = []
        with torch.inference_mode():
            for excerpt in excerpts:
                inputs = processor(excerpt, sampling_rate=24000, return_tensors="pt")
                hidden = model(**inputs).last_hidden_state.mean(dim=1).squeeze(0)
                vectors.append(hidden.cpu().float().numpy())
        source = np.mean(np.stack(vectors), axis=0)
        rng = np.random.default_rng(0x554D55534943)
        projection = rng.choice((-1.0, 1.0), size=(source.shape[0], 64)) / math.sqrt(64)
        reduced = source @ projection
        norm = float(np.linalg.norm(reduced)) or 1.0
        result = (reduced / norm).astype(np.float32)
        if not np.isfinite(result).all():
            raise ValueError("non_finite_embedding")
        return result.tolist()

    @staticmethod
    def _energy(excerpts: list[list[float]]) -> float:
        total = sum(sample * sample for excerpt in excerpts for sample in excerpt)
        count = sum(len(excerpt) for excerpt in excerpts)
        rms = math.sqrt(total / max(count, 1))
        return min(max(rms * 4, 0), 1)


@lru_cache(maxsize=1)
def configured_provider():
    provider = os.environ.get("UMUSIC_AUDIO_ANALYSIS_PROVIDER", "deterministic")
    if provider == "mert":
        return MERTAnalysisProvider()
    from umusic.apps.library.audio_analysis import DeterministicAnalysisProvider

    return DeterministicAnalysisProvider()
