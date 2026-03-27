from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Sequence

import numpy as np

from .config import FaceModuleConfig
from .database import SQLiteFaceAttendanceRepository
from .engine import ImageInput, OpenCVFaceEngine


@dataclass(slots=True)
class ImageValidationSummary:
    status: str
    reason: str
    face_count: int
    quality_score: float = 0.0
    detector_backend: str = ""


@dataclass(slots=True)
class EnrollmentSampleResult:
    sample_index: int
    status: str
    reason: str
    quality_score: float = 0.0
    detector_backend: str = ""


@dataclass(slots=True)
class EnrollmentSummary:
    status: str
    employee_id: str
    full_name: str
    required_samples: int
    enrolled_samples: int
    sample_results: list[EnrollmentSampleResult]


@dataclass(slots=True)
class AttendanceDecision:
    status: str
    action: str | None
    reason: str
    event_id: int | None = None


@dataclass(slots=True)
class RecognitionSummary:
    status: str
    reason: str
    employee_id: str | None = None
    full_name: str | None = None
    similarity: float = 0.0
    confidence: float = 0.0
    threshold: float = 0.0
    attendance: AttendanceDecision | None = None


class FaceAttendanceService:
    def __init__(
        self,
        repository: SQLiteFaceAttendanceRepository,
        engine: OpenCVFaceEngine,
        config: FaceModuleConfig,
    ) -> None:
        self.repository = repository
        self.engine = engine
        self.config = config

    def initialize(self) -> None:
        self.repository.init_db()

    def validate_image(self, image_input: ImageInput) -> ImageValidationSummary:
        validation = self.engine.validate_image(image_input)
        return ImageValidationSummary(
            status="valid" if validation.ok else "rejected",
            reason=validation.reason,
            face_count=validation.face_count,
            quality_score=validation.quality_score,
            detector_backend=self.engine.detector_backend,
        )

    def enroll_employee(
        self,
        employee_id: str,
        full_name: str,
        sample_images: Sequence[ImageInput],
        employee_code: str | None = None,
    ) -> EnrollmentSummary:
        self.initialize()

        if len(sample_images) != self.config.required_samples_per_employee:
            raise ValueError(
                f"Enrollment requires exactly {self.config.required_samples_per_employee} face samples."
            )

        sample_results: list[EnrollmentSampleResult] = []
        stored_embeddings: list[dict[str, object]] = []

        for sample_index, sample_image in enumerate(sample_images, start=1):
            try:
                embedding_result = self.engine.extract_embedding(sample_image)
            except ValueError as exc:
                sample_results.append(
                    EnrollmentSampleResult(
                        sample_index=sample_index,
                        status="rejected",
                        reason=str(exc),
                    )
                )
                return EnrollmentSummary(
                    status="failed",
                    employee_id=employee_id,
                    full_name=full_name,
                    required_samples=self.config.required_samples_per_employee,
                    enrolled_samples=0,
                    sample_results=sample_results,
                )

            stored_embeddings.append(
                {
                    "sample_index": sample_index,
                    "embedding": embedding_result.embedding,
                    "detector_backend": embedding_result.detector_backend,
                    "quality_score": embedding_result.quality_score,
                    "image_path": self._stringify_path(sample_image),
                }
            )
            sample_results.append(
                EnrollmentSampleResult(
                    sample_index=sample_index,
                    status="accepted",
                    reason="valid",
                    quality_score=embedding_result.quality_score,
                    detector_backend=embedding_result.detector_backend,
                )
            )

        self.repository.upsert_employee(
            employee_id=employee_id,
            full_name=full_name,
            employee_code=employee_code,
        )
        self.repository.replace_embeddings(employee_id, stored_embeddings)
        return EnrollmentSummary(
            status="completed",
            employee_id=employee_id,
            full_name=full_name,
            required_samples=self.config.required_samples_per_employee,
            enrolled_samples=len(stored_embeddings),
            sample_results=sample_results,
        )

    def recognize(
        self,
        image_input: ImageInput,
        source: str = "camera",
        mark_attendance: bool = True,
        captured_at: datetime | None = None,
    ) -> RecognitionSummary:
        self.initialize()
        captured_at = captured_at or datetime.now()
        settings = self.repository.get_settings()
        threshold = float(settings["match_threshold"])

        enrolled_embeddings = self.repository.get_all_embeddings()
        if not enrolled_embeddings:
            return RecognitionSummary(
                status="unknown",
                reason="No enrolled face embeddings found.",
                threshold=threshold,
            )

        try:
            probe = self.engine.extract_embedding(image_input)
        except ValueError as exc:
            return RecognitionSummary(
                status="rejected",
                reason=str(exc),
                threshold=threshold,
            )

        best_match = self._find_best_match(probe.embedding, enrolled_embeddings)
        if best_match is None:
            return RecognitionSummary(
                status="unknown",
                reason="No enrolled face embeddings found.",
                threshold=threshold,
            )

        similarity = round(best_match["similarity"], 4)
        confidence = round(self._confidence_from_similarity(similarity, threshold), 4)
        if similarity < threshold:
            return RecognitionSummary(
                status="unknown",
                reason="Face did not meet the match threshold.",
                similarity=similarity,
                confidence=confidence,
                threshold=threshold,
            )

        attendance = None
        if mark_attendance:
            attendance = self._mark_attendance(
                employee_id=best_match["employee_id"],
                similarity=similarity,
                confidence=confidence,
                source=source,
                image_path=self._stringify_path(image_input),
                captured_at=captured_at,
            )

        return RecognitionSummary(
            status="matched",
            reason="Matched against enrolled employee embeddings.",
            employee_id=best_match["employee_id"],
            full_name=best_match["full_name"],
            similarity=similarity,
            confidence=confidence,
            threshold=threshold,
            attendance=attendance,
        )

    def update_settings(
        self,
        duplicate_window_minutes: int | None = None,
        min_checkout_gap_minutes: int | None = None,
        match_threshold: float | None = None,
    ) -> None:
        self.initialize()
        self.repository.update_settings(
            duplicate_window_minutes=duplicate_window_minutes,
            min_checkout_gap_minutes=min_checkout_gap_minutes,
            match_threshold=match_threshold,
        )

    def _find_best_match(
        self,
        probe_embedding: np.ndarray,
        stored_embeddings: list[dict[str, object]],
    ) -> dict[str, object] | None:
        grouped_scores: dict[str, list[dict[str, object]]] = defaultdict(list)
        employee_names: dict[str, str] = {}

        for stored in stored_embeddings:
            similarity = self.engine.cosine_similarity(
                probe_embedding,
                stored["embedding"],  # type: ignore[arg-type]
            )
            employee_id = str(stored["employee_id"])
            employee_names[employee_id] = str(stored["full_name"])
            grouped_scores[employee_id].append(
                {
                    "similarity": similarity,
                    "quality_score": float(stored["quality_score"]),
                }
            )

        best_result: dict[str, object] | None = None
        for employee_id, scores in grouped_scores.items():
            sorted_scores = sorted(scores, key=lambda item: item["similarity"], reverse=True)
            top_scores = sorted_scores[: min(3, len(sorted_scores))]
            weighted_similarity = self._weighted_similarity(top_scores)
            employee_result = {
                "employee_id": employee_id,
                "full_name": employee_names[employee_id],
                "similarity": weighted_similarity,
            }
            if best_result is None or weighted_similarity > float(best_result["similarity"]):
                best_result = employee_result
        return best_result

    @staticmethod
    def _weighted_similarity(scores: list[dict[str, float]]) -> float:
        total_weight = 0.0
        weighted_sum = 0.0
        best_sample = max(score["similarity"] for score in scores)
        for score in scores:
            weight = max(0.2, score["quality_score"])
            total_weight += weight
            weighted_sum += score["similarity"] * weight

        averaged_similarity = weighted_sum / max(total_weight, 1e-6)
        return (0.70 * best_sample) + (0.30 * averaged_similarity)

    def _mark_attendance(
        self,
        employee_id: str,
        similarity: float,
        confidence: float,
        source: str,
        image_path: str | None,
        captured_at: datetime,
    ) -> AttendanceDecision:
        settings = self.repository.get_settings()
        duplicate_window_minutes = int(settings["duplicate_window_minutes"])
        min_checkout_gap_minutes = int(settings["min_checkout_gap_minutes"])
        event_date = captured_at.date().isoformat()
        daily_events = self.repository.get_daily_events(employee_id, event_date)

        if len(daily_events) >= 2:
            return AttendanceDecision(
                status="rejected",
                action=None,
                reason="Check-in and check-out are already completed for today.",
            )

        if daily_events:
            last_event = daily_events[-1]
            last_captured_at = datetime.fromisoformat(last_event["captured_at"])
            minutes_since_last = (captured_at - last_captured_at).total_seconds() / 60

            if minutes_since_last < duplicate_window_minutes:
                return AttendanceDecision(
                    status="rejected",
                    action=None,
                    reason="Rapid duplicate recognition blocked.",
                )

            if last_event["event_type"] == "check_in":
                if minutes_since_last < min_checkout_gap_minutes:
                    return AttendanceDecision(
                        status="rejected",
                        action=None,
                        reason="Check-out attempted too soon after check-in.",
                    )
                action = "check_out"
            else:
                return AttendanceDecision(
                    status="rejected",
                    action=None,
                    reason="Attendance is already closed for today.",
                )
        else:
            action = "check_in"

        event_id = self.repository.add_attendance_event(
            employee_id=employee_id,
            event_date=event_date,
            event_type=action,
            confidence=confidence,
            similarity=similarity,
            captured_at=captured_at.isoformat(timespec="seconds"),
            source=source,
            image_path=image_path,
        )
        return AttendanceDecision(
            status="marked",
            action=action,
            reason="Attendance marked successfully.",
            event_id=event_id,
        )

    @staticmethod
    def _confidence_from_similarity(similarity: float, threshold: float) -> float:
        if similarity <= 0:
            return 0.0
        if similarity < threshold:
            return (similarity / max(threshold, 1e-6)) * 0.49
        return 0.50 + ((similarity - threshold) / max(1.0 - threshold, 1e-6)) * 0.50

    @staticmethod
    def _stringify_path(image_input: ImageInput) -> str | None:
        if isinstance(image_input, (str, Path)):
            return str(image_input)
        return None
