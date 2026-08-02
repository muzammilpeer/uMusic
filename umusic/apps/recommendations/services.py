import hashlib
import json
import math
from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

from umusic.apps.accounts.models import User
from umusic.apps.contexts.models import ContextForgetRecord
from umusic.apps.events.models import ListeningEvent, PlayFact
from umusic.apps.recommendations.models import Affinity, LearningConfiguration, LearningRun

DEFAULT_WEIGHTS = {
    "explicit_like": 5.0,
    "explicit_dislike": -8.0,
    "completed": 1.5,
    "replayed": 2.5,
    "early_skip": -2.0,
    "late_skip": -0.25,
    "queue_removed": -0.75,
}
ALGORITHM_VERSION = "rules-v1"


@dataclass
class EvidenceAccumulator:
    target_type: str
    target_id: str
    target_label: str
    context_type: str
    context_key: str
    positive: float = 0.0
    negative: float = 0.0
    sample_ids: set[str] = field(default_factory=set)
    explicit_preference: int = 0
    explicit_at: datetime | None = None
    reasons: dict[str, dict[str, float | int]] = field(default_factory=dict)
    last_observation: datetime | None = None

    def add(
        self,
        playback_id: str,
        code: str,
        contribution: float,
        observed_at: datetime,
        explicit: int = 0,
    ) -> None:
        self.sample_ids.add(playback_id)
        if contribution >= 0:
            self.positive += contribution
        else:
            self.negative += abs(contribution)
        reason = self.reasons.setdefault(code, {"count": 0, "contribution": 0.0})
        reason["count"] = int(reason["count"]) + 1
        reason["contribution"] = round(float(reason["contribution"]) + contribution, 6)
        if explicit and (self.explicit_at is None or observed_at >= self.explicit_at):
            self.explicit_preference = explicit
            self.explicit_at = observed_at
        self.last_observation = max(self.last_observation or observed_at, observed_at)


def active_configuration() -> LearningConfiguration:
    configuration, _ = LearningConfiguration.objects.get_or_create(
        version=ALGORITHM_VERSION,
        defaults={
            "weights": DEFAULT_WEIGHTS,
            "implicit_half_life_days": 90,
            "global_min_evidence": 1,
            "context_min_evidence": 3,
            "is_active": True,
        },
    )
    return configuration


def _signal(fact: PlayFact, weights: dict[str, float]) -> tuple[str, float, int]:
    if fact.explicit_feedback < 0:
        return "explicit_dislike", weights["explicit_dislike"], -1
    if fact.explicit_feedback > 0:
        return "explicit_like", weights["explicit_like"], 1
    if fact.replayed:
        return "replayed", weights["replayed"], 0
    if fact.completed:
        return "completed", weights["completed"], 0
    if fact.early_skip:
        return "early_skip", weights["early_skip"], 0
    if fact.skipped:
        return "late_skip", weights["late_skip"], 0
    return "neutral_play", 0.0, 0


def _contexts(
    event: ListeningEvent | None, forgotten: dict[str, datetime]
) -> list[tuple[str, str]]:
    result: list[tuple[str, str]] = [(str(Affinity.Context.GLOBAL), "")]
    if event is None or event.context_snapshot is None:
        return result
    snapshot = event.context_snapshot
    result.extend(
        [
            (str(Affinity.Context.ACTIVITY), snapshot.activity_kind),
            (str(Affinity.Context.TIME), snapshot.time_bucket),
        ]
    )
    if snapshot.geofence_reference:
        key = str(snapshot.geofence_reference)
        cutoff = forgotten.get(key)
        if cutoff is None or event.client_timestamp > cutoff:
            result.append((str(Affinity.Context.PLACE), key))
    return result


def rebuild_affinities(owner: User) -> LearningRun:
    configuration = active_configuration()
    run = LearningRun.objects.create(owner=owner, configuration=configuration)
    try:
        facts = list(PlayFact.objects.filter(owner=owner).select_related("track", "track__artist"))
        reference_time = max((fact.last_event_at for fact in facts), default=timezone.now())
        context_events = {
            event.playback_id: event
            for event in ListeningEvent.objects.filter(owner=owner, context_snapshot__isnull=False)
            .select_related("context_snapshot")
            .order_by("playback_id", "client_timestamp")
        }
        queue_removed = set(
            ListeningEvent.objects.filter(
                owner=owner, event_type=ListeningEvent.Type.QUEUE_REMOVED
            ).values_list("playback_id", flat=True)
        )
        forgotten = {
            str(item.geofence_reference): item.forgotten_at
            for item in ContextForgetRecord.objects.filter(owner=owner).order_by("forgotten_at")
        }
        weights = {**DEFAULT_WEIGHTS, **configuration.weights}
        groups: dict[tuple[str, str, str, str], EvidenceAccumulator] = {}
        for fact in facts:
            code, base, explicit = _signal(fact, weights)
            age_days = max(0.0, (reference_time - fact.last_event_at).total_seconds() / 86400)
            decay = 1.0 if explicit else 0.5 ** (age_days / configuration.implicit_half_life_days)
            signals = [(code, base * decay, explicit)]
            if fact.playback_id in queue_removed:
                signals.append(("queue_removed", weights["queue_removed"] * decay, 0))
            targets: list[tuple[str, str, str]] = [
                (str(Affinity.Target.TRACK), str(fact.track_id), fact.track.title),
                (str(Affinity.Target.ARTIST), str(fact.track.artist_id), fact.track.artist.name),
            ]
            targets.extend(
                (str(Affinity.Target.GENRE), genre.casefold(), genre) for genre in fact.track.genres
            )
            for context_type, context_key in _contexts(
                context_events.get(fact.playback_id), forgotten
            ):
                for target_type, target_id, label in targets:
                    group_key = (target_type, target_id, context_type, context_key)
                    group = groups.setdefault(
                        group_key,
                        EvidenceAccumulator(
                            target_type, target_id, label, context_type, context_key
                        ),
                    )
                    for signal_code, contribution, signal_explicit in signals:
                        hard_explicit = (
                            signal_explicit if target_type == Affinity.Target.TRACK else 0
                        )
                        group.add(
                            str(fact.playback_id),
                            signal_code,
                            contribution,
                            fact.last_event_at,
                            hard_explicit,
                        )
        affinities = []
        canonical = []
        for sorted_key in sorted(groups):
            group = groups[sorted_key]
            count = len(group.sample_ids)
            minimum = (
                configuration.global_min_evidence
                if group.context_type == Affinity.Context.GLOBAL
                else configuration.context_min_evidence
            )
            raw = group.positive - group.negative
            confidence = count / (count + minimum)
            if count < minimum:
                confidence *= count / minimum
            score = math.tanh(raw / 5.0)
            if group.explicit_preference < 0:
                score, confidence = -1.0, 1.0
            elif group.explicit_preference > 0:
                score, confidence = 1.0, 1.0
            evidence = {code: group.reasons[code] for code in sorted(group.reasons)}
            item = Affinity(
                owner=owner,
                configuration=configuration,
                target_type=group.target_type,
                target_id=group.target_id,
                target_label=group.target_label,
                context_type=group.context_type,
                context_key=group.context_key,
                score=Decimal(f"{score:.4f}"),
                confidence=Decimal(f"{confidence:.4f}"),
                positive_evidence=Decimal(f"{group.positive:.4f}"),
                negative_evidence=Decimal(f"{group.negative:.4f}"),
                sample_count=count,
                explicit_preference=group.explicit_preference,
                evidence=evidence,
                last_observation=group.last_observation or reference_time,
            )
            affinities.append(item)
            canonical.append([*sorted_key, f"{score:.4f}", f"{confidence:.4f}", evidence])
        digest = hashlib.sha256(json.dumps(canonical, sort_keys=True).encode()).hexdigest()
        with transaction.atomic():
            Affinity.objects.filter(owner=owner).delete()
            Affinity.objects.bulk_create(affinities)
            run.status = LearningRun.Status.COMPLETED
            run.affinity_count = len(affinities)
            run.evidence_digest = digest
            run.completed_at = timezone.now()
            run.save()
        return run
    except Exception as error:
        run.status = LearningRun.Status.FAILED
        run.error = str(error)
        run.completed_at = timezone.now()
        run.save()
        raise


def reset_learning(owner: User) -> int:
    deleted, _ = Affinity.objects.filter(owner=owner).delete()
    return deleted
