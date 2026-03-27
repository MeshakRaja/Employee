import base64
import sqlite3
import sys
import os
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Any, Dict

import numpy as np

# Updated Paths for Render compatibility
BACKEND_ROOT = Path(__file__).resolve().parent
APP_DATABASE_PATH = BACKEND_ROOT / "students.db"
FACE_DATA_ROOT = BACKEND_ROOT / "face_data"
FACE_DATABASE_PATH = FACE_DATA_ROOT / "attendance_face.db"
# Fixed: Pointing to the correct folder where .onnx files are located
FACE_MODEL_DIR = FACE_DATA_ROOT / "models"
FACE_CAPTURE_DIR = FACE_DATA_ROOT / "captures"

# Ensure Backend root is in sys.path so 'face_attendance' can be found
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

if TYPE_CHECKING:
    from face_attendance import FaceAttendanceService


def _decode_base64_image(image_b64: str) -> bytes | None:
    try:
        clean = image_b64.split(",")[-1]
        return base64.b64decode(clean)
    except Exception:
        return None


def _to_plain_value(value: Any) -> Any:
    if is_dataclass(value):
        return {key: _to_plain_value(item) for key, item in asdict(value).items()}
    if isinstance(value, dict):
        return {key: _to_plain_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_to_plain_value(item) for item in value]
    if isinstance(value, np.ndarray):
        return value.tolist()
    return value


_service: "FaceAttendanceService | None" = None

def _get_service() -> "FaceAttendanceService":
    global _service
    if _service is not None:
        return _service

    from face_attendance import (  # noqa: E402
        FaceAttendanceService,
        FaceModuleConfig,
        OpenCVFaceEngine,
        SQLiteFaceAttendanceRepository,
    )

    config = FaceModuleConfig(
        database_path=FACE_DATABASE_PATH,
        model_dir=FACE_MODEL_DIR,
        capture_dir=FACE_CAPTURE_DIR,
        required_samples_per_employee=1,
        use_sface_if_available=True,
    )

    repository = SQLiteFaceAttendanceRepository(config)
    engine = OpenCVFaceEngine(config)
    service = FaceAttendanceService(repository=repository, engine=engine, config=config)
    service.initialize()

    FACE_DATA_ROOT.mkdir(parents=True, exist_ok=True)
    FACE_MODEL_DIR.mkdir(parents=True, exist_ok=True)
    FACE_CAPTURE_DIR.mkdir(parents=True, exist_ok=True)

    _service = service
    return _service


def enroll_employee(employee_id: str, full_name: str, image_b64: str) -> Dict[str, Any]:
    global _service
    _service = None
    image_bytes = _decode_base64_image(image_b64)
    if image_bytes is None:
        return {"status": "error", "message": "Invalid face image data"}

    try:
        service = _get_service()
        # Relaxed settings for mobile captures
        service.engine.config.detector_score_threshold = 0.35
        service.engine.config.min_face_size = 20
        
        result = service.enroll_employee(
            employee_id=employee_id,
            full_name=full_name,
            sample_images=[image_bytes],
        )
        result_dict = _to_plain_value(result)
        if result_dict.get("status") != "completed":
            return {"status": "error", "message": "No Face Detected. Use better lighting and keep phone steady."}
        return result_dict
    except Exception as exc:
        return {"status": "error", "message": str(exc)}


def recognize_face(
    image_b64: str,
    source: str = "mobile",
    mark_attendance: bool = False,
) -> Dict[str, Any]:
    image_bytes = _decode_base64_image(image_b64)
    if image_bytes is None:
        return {"status": "error", "reason": "Invalid face image data"}

    try:
        service = _get_service()
        # Ensure model is ready for recognition too
        service.engine.config.detector_score_threshold = 0.35

        result = service.recognize(
            image_input=image_bytes,
            source=source,
            mark_attendance=mark_attendance,
        )
        return _to_plain_value(result)
    except Exception as exc:
        return {"status": "error", "reason": str(exc)}

def delete_employee_face(employee_id: str) -> Dict[str, Any]:
    try:
        service = _get_service()
        repository = service.repository
        with repository._connect() as connection:
            connection.execute("DELETE FROM employees WHERE employee_id = ?", (employee_id,))
        return {"status": "completed"}
    except Exception as exc:
        return {"status": "error", "message": str(exc)}
