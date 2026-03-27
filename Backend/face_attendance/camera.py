from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np

from .engine import DetectedFace, PoseEstimate, ValidationResult
from .service import EnrollmentSummary, FaceAttendanceService, RecognitionSummary


@dataclass(slots=True)
class CameraStep:
    key: str
    title: str
    instruction: str


@dataclass(slots=True)
class LiveEnrollmentResult:
    status: str
    message: str
    saved_images: list[str]
    summary: EnrollmentSummary | None = None


@dataclass(slots=True)
class LiveRecognitionResult:
    status: str
    message: str
    image_path: str | None = None
    recognition: RecognitionSummary | None = None


DEFAULT_CAMERA_STEPS = [
    CameraStep("front", "Front", "Look straight at the camera"),
    CameraStep("left", "Left", "Turn slightly to your left"),
    CameraStep("right", "Right", "Turn slightly to your right"),
    CameraStep("up", "Up", "Raise your chin a little"),
    CameraStep("down", "Down", "Lower your chin a little"),
]


class LiveCameraEnrollment:
    def __init__(self, service: FaceAttendanceService) -> None:
        self.service = service
        self.engine = service.engine
        self.config = service.config

    def run(
        self,
        employee_id: str,
        full_name: str,
        employee_code: str | None = None,
        camera_index: int = 0,
    ) -> LiveEnrollmentResult:
        steps = self._build_steps()
        save_dir = self.config.enrollment_capture_dir / employee_id
        save_dir.mkdir(parents=True, exist_ok=True)

        capture = self._open_camera(camera_index, self.config)
        saved_images: list[str] = []
        step_index = 0
        stable_frames = 0
        manual_message = ""

        try:
            while step_index < len(steps):
                ok, frame = capture.read()
                if not ok:
                    continue
                frame = cv2.flip(frame, 1)
                display_frame = frame.copy()

                validation = self.engine.validate_image(frame)
                pose = (
                    self.engine.estimate_pose(validation.face)
                    if validation.face is not None
                    else None
                )
                current_step = steps[step_index]
                ready, guidance = self._step_ready(
                    current_step,
                    validation,
                    pose,
                    frame.shape,
                )

                if ready:
                    stable_frames += 1
                else:
                    stable_frames = 0

                self._draw_enrollment_overlay(
                    display_frame=display_frame,
                    step=current_step,
                    step_index=step_index,
                    total_steps=len(steps),
                    validation=validation,
                    pose=pose,
                    guidance=manual_message or guidance,
                    stable_frames=stable_frames,
                )
                manual_message = ""

                cv2.imshow("Live Face Enrollment", display_frame)
                key = cv2.waitKey(1) & 0xFF

                if key in (27, ord("q")):
                    return LiveEnrollmentResult(
                        status="cancelled",
                        message="Live enrollment cancelled.",
                        saved_images=saved_images,
                    )

                if key in (ord("c"), 32):
                    if validation.ok and validation.face is not None:
                        saved_images.append(
                            self._save_enrollment_frame(
                                frame=frame,
                                save_dir=save_dir,
                                sample_number=step_index + 1,
                                pose_name=current_step.key,
                            )
                        )
                        manual_message = "Captured sample manually."
                        step_index += 1
                        stable_frames = 0
                        continue
                    manual_message = validation.reason

                if stable_frames >= self.config.camera_stable_frames:
                    saved_images.append(
                        self._save_enrollment_frame(
                            frame=frame,
                            save_dir=save_dir,
                            sample_number=step_index + 1,
                            pose_name=current_step.key,
                        )
                    )
                    manual_message = "Captured automatically."
                    step_index += 1
                    stable_frames = 0

            summary = self.service.enroll_employee(
                employee_id=employee_id,
                full_name=full_name,
                employee_code=employee_code,
                sample_images=saved_images,
            )
            result_status = "completed" if summary.status == "completed" else summary.status
            result_message = (
                "Live enrollment completed successfully."
                if summary.status == "completed"
                else f"Live enrollment finished, but enrollment {summary.status}."
            )
            return LiveEnrollmentResult(
                status=result_status,
                message=result_message,
                saved_images=saved_images,
                summary=summary,
            )
        finally:
            capture.release()
            cv2.destroyWindow("Live Face Enrollment")

    def _step_ready(
        self,
        step: CameraStep,
        validation: ValidationResult,
        pose: PoseEstimate | None,
        frame_shape: tuple[int, ...],
    ) -> tuple[bool, str]:
        if not validation.ok or validation.face is None:
            return False, validation.reason
        if validation.quality_score < self.config.min_capture_quality:
            return False, "Hold still for a clearer sample."
        if not self._is_face_centered(validation.face, frame_shape):
            return False, "Center your face in the guide box."
        if step.key == "front":
            if pose is None:
                return True, "Hold still for auto capture."
            if abs(pose.yaw) <= 0.12 and abs(pose.pitch) <= 0.10:
                return True, "Hold still for auto capture."
            return False, "Look straight at the camera."
        if pose is None:
            return (
                False,
                "Auto angle approval needs YuNet/SFace models. Press C to capture manually.",
            )
        if step.key == "left":
            if pose.yaw <= -0.15:
                return True, "Hold still for auto capture."
            return False, "Turn slightly to your left."
        if step.key == "right":
            if pose.yaw >= 0.15:
                return True, "Hold still for auto capture."
            return False, "Turn slightly to your right."
        if step.key == "up":
            if pose.pitch <= -0.08:
                return True, "Hold still for auto capture."
            return False, "Raise your chin a little."
        if pose.pitch >= 0.08:
            return True, "Hold still for auto capture."
        return False, "Lower your chin a little."

    def _draw_enrollment_overlay(
        self,
        display_frame: np.ndarray,
        step: CameraStep,
        step_index: int,
        total_steps: int,
        validation: ValidationResult,
        pose: PoseEstimate | None,
        guidance: str,
        stable_frames: int,
    ) -> None:
        self._draw_guide_box(display_frame)
        self._draw_face(display_frame, validation.face)
        lines = [
            f"Step {step_index + 1}/{total_steps}: {step.title}",
            step.instruction,
            f"Backend: {self.engine.detector_backend}",
            f"Quality: {validation.quality_score:.2f}",
            guidance,
        ]
        if pose is not None:
            lines.append(
                f"Pose: {pose.label} yaw={pose.yaw:.2f} pitch={pose.pitch:.2f}"
            )
        if self.engine.detector_backend != "opencv_sface":
            lines.append("Tip: press C or Space to capture manual samples.")
        else:
            lines.append(
                f"Auto capture countdown: {max(self.config.camera_stable_frames - stable_frames, 0)}"
            )
        self._draw_lines(display_frame, lines, color=(0, 255, 0))

    def _save_enrollment_frame(
        self,
        frame: np.ndarray,
        save_dir: Path,
        sample_number: int,
        pose_name: str,
    ) -> str:
        image_path = save_dir / f"{sample_number:02d}_{pose_name}.jpg"
        cv2.imwrite(str(image_path), frame)
        return str(image_path)

    def _build_steps(self) -> list[CameraStep]:
        steps = list(DEFAULT_CAMERA_STEPS[: self.config.required_samples_per_employee])
        while len(steps) < self.config.required_samples_per_employee:
            steps.append(
                CameraStep(
                    key="front",
                    title=f"Front {len(steps) + 1}",
                    instruction="Look straight at the camera",
                )
            )
        return steps

    @staticmethod
    def _open_camera(
        camera_index: int,
        config: object | None = None,
    ) -> cv2.VideoCapture:
        capture = cv2.VideoCapture(camera_index)
        if not capture.isOpened():
            raise RuntimeError(f"Unable to open camera index {camera_index}.")
        if config is not None:
            width = getattr(config, "camera_frame_width", 1280)
            height = getattr(config, "camera_frame_height", 720)
            capture.set(cv2.CAP_PROP_FRAME_WIDTH, width)
            capture.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
        return capture

    def _is_face_centered(
        self,
        face: DetectedFace,
        frame_shape: tuple[int, ...],
    ) -> bool:
        frame_height, frame_width = frame_shape[:2]
        face_center_x = face.box.x + (face.box.w / 2)
        face_center_y = face.box.y + (face.box.h / 2)
        guide_x1, guide_y1, guide_x2, guide_y2 = self._guide_box(frame_shape)
        return (
            guide_x1 <= face_center_x <= guide_x2
            and guide_y1 <= face_center_y <= guide_y2
        )

    @staticmethod
    def _guide_box(frame_shape: tuple[int, ...]) -> tuple[int, int, int, int]:
        frame_height, frame_width = frame_shape[:2]
        box_width = int(frame_width * 0.36)
        box_height = int(frame_height * 0.56)
        x1 = int((frame_width - box_width) / 2)
        y1 = int((frame_height - box_height) / 2)
        x2 = x1 + box_width
        y2 = y1 + box_height
        return x1, y1, x2, y2

    def _draw_guide_box(self, frame: np.ndarray) -> None:
        x1, y1, x2, y2 = self._guide_box(frame.shape)
        cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 200, 255), 2)

    @staticmethod
    def _draw_face(frame: np.ndarray, face: DetectedFace | None) -> None:
        if face is None:
            return
        x1 = face.box.x
        y1 = face.box.y
        x2 = face.box.x + face.box.w
        y2 = face.box.y + face.box.h
        cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
        if face.landmarks is None:
            return
        for point in [
            face.landmarks.eye_a,
            face.landmarks.eye_b,
            face.landmarks.nose,
            face.landmarks.mouth_a,
            face.landmarks.mouth_b,
        ]:
            cv2.circle(frame, (int(point.x), int(point.y)), 3, (255, 255, 0), -1)

    @staticmethod
    def _draw_lines(
        frame: np.ndarray,
        lines: list[str],
        color: tuple[int, int, int],
    ) -> None:
        cv2.rectangle(frame, (16, 16), (760, 210), (0, 0, 0), -1)
        for index, line in enumerate(lines):
            cv2.putText(
                frame,
                line,
                (28, 44 + (index * 26)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.68,
                color,
                2,
                cv2.LINE_AA,
            )


class LiveCameraRecognition:
    def __init__(self, service: FaceAttendanceService) -> None:
        self.service = service
        self.engine = service.engine
        self.config = service.config

    def run(
        self,
        camera_index: int = 0,
        source: str = "live_camera",
    ) -> LiveRecognitionResult:
        capture = LiveCameraEnrollment._open_camera(camera_index, self.config)
        frame_count = 0
        candidate_employee_id: str | None = None
        candidate_frames = 0
        latest_message = "Scanning for a valid face..."
        latest_recognition: RecognitionSummary | None = None
        candidate_frame: np.ndarray | None = None

        try:
            while True:
                ok, frame = capture.read()
                if not ok:
                    continue
                frame = cv2.flip(frame, 1)
                display_frame = frame.copy()
                validation = self.engine.validate_image(frame)
                pose = (
                    self.engine.estimate_pose(validation.face)
                    if validation.face is not None
                    else None
                )

                frame_count += 1
                if (
                    validation.ok
                    and frame_count % self.config.recognition_scan_interval == 0
                ):
                    preview = self.service.recognize(
                        image_input=frame,
                        source=f"{source}_preview",
                        mark_attendance=False,
                    )
                    latest_recognition = preview

                    if preview.status == "matched" and preview.employee_id is not None:
                        latest_message = (
                            f"Match candidate: {preview.full_name} "
                            f"({preview.confidence:.2f})"
                        )
                        if preview.employee_id == candidate_employee_id:
                            candidate_frames += 1
                        else:
                            candidate_employee_id = preview.employee_id
                            candidate_frames = 1
                            candidate_frame = frame.copy()

                        if candidate_frames >= self.config.recognition_stable_frames:
                            image_path = self._save_recognition_frame(
                                frame=candidate_frame if candidate_frame is not None else frame,
                                employee_id=preview.employee_id,
                            )
                            final_result = self.service.recognize(
                                image_input=image_path,
                                source=source,
                                mark_attendance=True,
                            )
                            return LiveRecognitionResult(
                                status="completed",
                                message=self._final_message(final_result),
                                image_path=image_path,
                                recognition=final_result,
                            )
                    else:
                        latest_message = preview.reason
                        candidate_employee_id = None
                        candidate_frames = 0
                        candidate_frame = None
                elif not validation.ok:
                    latest_message = validation.reason
                    latest_recognition = None
                    candidate_employee_id = None
                    candidate_frames = 0
                    candidate_frame = None

                self._draw_recognition_overlay(
                    display_frame=display_frame,
                    validation=validation,
                    pose=pose,
                    latest_message=latest_message,
                    latest_recognition=latest_recognition,
                    candidate_frames=candidate_frames,
                )
                cv2.imshow("Live Face Recognition", display_frame)
                key = cv2.waitKey(1) & 0xFF
                if key in (27, ord("q")):
                    return LiveRecognitionResult(
                        status="cancelled",
                        message="Live recognition cancelled.",
                    )
        finally:
            capture.release()
            cv2.destroyWindow("Live Face Recognition")

    def _draw_recognition_overlay(
        self,
        display_frame: np.ndarray,
        validation: ValidationResult,
        pose: PoseEstimate | None,
        latest_message: str,
        latest_recognition: RecognitionSummary | None,
        candidate_frames: int,
    ) -> None:
        LiveCameraEnrollment._draw_face(display_frame, validation.face)
        lines = [
            "Live attendance recognition",
            f"Backend: {self.engine.detector_backend}",
            f"Quality: {validation.quality_score:.2f}",
            latest_message,
            f"Stable match frames: {candidate_frames}/{self.config.recognition_stable_frames}",
        ]
        if pose is not None:
            lines.append(
                f"Pose: {pose.label} yaw={pose.yaw:.2f} pitch={pose.pitch:.2f}"
            )
        if latest_recognition is not None and latest_recognition.employee_id is not None:
            lines.append(
                f"Employee: {latest_recognition.full_name} / {latest_recognition.employee_id}"
            )
        LiveCameraEnrollment._draw_lines(display_frame, lines, color=(0, 255, 255))

    def _save_recognition_frame(self, frame: np.ndarray, employee_id: str) -> str:
        day_dir = self.config.recognition_capture_dir / datetime.now().strftime("%Y-%m-%d")
        day_dir.mkdir(parents=True, exist_ok=True)
        image_path = day_dir / (
            f"{employee_id}_{datetime.now().strftime('%H%M%S')}.jpg"
        )
        cv2.imwrite(str(image_path), frame)
        return str(image_path)

    @staticmethod
    def _final_message(result: RecognitionSummary) -> str:
        if result.attendance is None:
            return result.reason
        return f"{result.full_name}: {result.attendance.reason}"
