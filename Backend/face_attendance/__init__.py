from .config import FaceModuleConfig
from .database import SQLiteFaceAttendanceRepository
from .engine import OpenCVFaceEngine
from .service import FaceAttendanceService, ImageValidationSummary

__all__ = [
    "FaceAttendanceService",
    "FaceModuleConfig",
    "ImageValidationSummary",
    "LiveCameraEnrollment",
    "LiveCameraRecognition",
    "OpenCVFaceEngine",
    "SQLiteFaceAttendanceRepository",
]


def __getattr__(name: str):
    if name in {"LiveCameraEnrollment", "LiveCameraRecognition"}:
        from .camera import LiveCameraEnrollment, LiveCameraRecognition

        exports = {
            "LiveCameraEnrollment": LiveCameraEnrollment,
            "LiveCameraRecognition": LiveCameraRecognition,
        }
        return exports[name]
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
