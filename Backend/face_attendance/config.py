from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(slots=True)
class FaceModuleConfig:
    database_path: Path = Path("attendance_face.db")
    model_dir: Path = Path("models")
    capture_dir: Path = Path("captures")
    required_samples_per_employee: int = 5
    match_threshold: float = 0.88
    min_face_size: int = 40
    blur_threshold: float = 30.0
    min_brightness: float = 20.0
    max_brightness: float = 250.0
    duplicate_window_minutes: int = 5
    min_checkout_gap_minutes: int = 30
    detector_score_threshold: float = 0.55
    use_sface_if_available: bool = True
    hog_face_size: int = 160
    min_capture_quality: float = 0.35
    camera_frame_width: int = 1280
    camera_frame_height: int = 720
    camera_stable_frames: int = 8
    recognition_stable_frames: int = 4
    recognition_scan_interval: int = 4

    @property
    def yunet_model_path(self) -> Path:
        return self.model_dir / "face_detection_yunet_2023mar.onnx"

    @property
    def sface_model_path(self) -> Path:
        return self.model_dir / "face_recognition_sface_2021dec.onnx"

    @property
    def enrollment_capture_dir(self) -> Path:
        return self.capture_dir / "enrollment"

    @property
    def recognition_capture_dir(self) -> Path:
        return self.capture_dir / "recognitions"
