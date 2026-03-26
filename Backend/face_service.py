import base64
import sqlite3
import sys
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Any, Dict

import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parents[1]
FACE_MODULE_ROOT = PROJECT_ROOT / "Face_Recoganization"
BACKEND_ROOT = PROJECT_ROOT / "Backend"
APP_DATABASE_PATH = BACKEND_ROOT / "students.db"
FACE_DATA_ROOT = BACKEND_ROOT / "face_data"
FACE_DATABASE_PATH = FACE_DATA_ROOT / "attendance_face.db"
FACE_MODEL_DIR = FACE_DATA_ROOT / "models"
FACE_CAPTURE_DIR = FACE_DATA_ROOT / "captures"
LEGACY_FACE_DATABASE_PATH = FACE_MODULE_ROOT / "attendance_face.db"

if str(FACE_MODULE_ROOT) not in sys.path:
    sys.path.insert(0, str(FACE_MODULE_ROOT))

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


def _copy_legacy_face_data(target_database_path: Path) -> None:
    if not LEGACY_FACE_DATABASE_PATH.exists() or not target_database_path.exists():
        return

    with sqlite3.connect(target_database_path) as target_connection:
        employee_count = target_connection.execute(
            "SELECT COUNT(*) FROM employees"
        ).fetchone()[0]
        if employee_count:
            return

    with sqlite3.connect(LEGACY_FACE_DATABASE_PATH) as legacy_connection:
        legacy_connection.row_factory = sqlite3.Row
        employees = legacy_connection.execute(
            """
            SELECT employee_id, employee_code, full_name, is_active, created_at, updated_at
            FROM employees
            """
        ).fetchall()
        embeddings = legacy_connection.execute(
            """
            SELECT employee_id, sample_index, embedding, detector_backend, quality_score, image_path, created_at
            FROM face_embeddings
            """
        ).fetchall()
        events = legacy_connection.execute(
            """
            SELECT employee_id, event_date, event_type, confidence, similarity, captured_at, source, image_path, created_at
            FROM attendance_events
            """
        ).fetchall()
        settings = legacy_connection.execute(
            """
            SELECT duplicate_window_minutes, min_checkout_gap_minutes, match_threshold, updated_at
            FROM attendance_settings
            WHERE settings_id = 1
            """
        ).fetchone()

    with sqlite3.connect(target_database_path) as target_connection:
        target_connection.execute("PRAGMA foreign_keys = ON")
        target_connection.executemany(
            """
            INSERT OR REPLACE INTO employees (
                employee_id,
                employee_code,
                full_name,
                is_active,
                created_at,
                updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    row["employee_id"],
                    row["employee_code"],
                    row["full_name"],
                    row["is_active"],
                    row["created_at"],
                    row["updated_at"],
                )
                for row in employees
            ],
        )
        target_connection.executemany(
            """
            INSERT OR REPLACE INTO face_embeddings (
                employee_id,
                sample_index,
                embedding,
                detector_backend,
                quality_score,
                image_path,
                created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    row["employee_id"],
                    row["sample_index"],
                    row["embedding"],
                    row["detector_backend"],
                    row["quality_score"],
                    row["image_path"],
                    row["created_at"],
                )
                for row in embeddings
            ],
        )
        target_connection.executemany(
            """
            INSERT INTO attendance_events (
                employee_id,
                event_date,
                event_type,
                confidence,
                similarity,
                captured_at,
                source,
                image_path,
                created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    row["employee_id"],
                    row["event_date"],
                    row["event_type"],
                    row["confidence"],
                    row["similarity"],
                    row["captured_at"],
                    row["source"],
                    row["image_path"],
                    row["created_at"],
                )
                for row in events
            ],
        )
        if settings is not None:
            target_connection.execute(
                """
                UPDATE attendance_settings
                SET
                    duplicate_window_minutes = ?,
                    min_checkout_gap_minutes = ?,
                    match_threshold = ?,
                    updated_at = ?
                WHERE settings_id = 1
                """,
                (
                    settings["duplicate_window_minutes"],
                    settings["min_checkout_gap_minutes"],
                    settings["match_threshold"],
                    settings["updated_at"],
                ),
            )


def _sync_face_records_with_app_database(target_database_path: Path) -> None:
    if not APP_DATABASE_PATH.exists() or not target_database_path.exists():
        return

    with sqlite3.connect(APP_DATABASE_PATH) as app_connection:
        app_rows = app_connection.execute(
            "SELECT employee_id, name FROM employees"
        ).fetchall()

    if not app_rows:
        return

    canonical_employees = {
        str(employee_id).strip().lower(): {
            "employee_id": str(employee_id).strip(),
            "full_name": str(full_name).strip(),
        }
        for employee_id, full_name in app_rows
        if employee_id
    }

    with sqlite3.connect(target_database_path) as target_connection:
        target_connection.execute("PRAGMA foreign_keys = ON")
        target_connection.row_factory = sqlite3.Row
        stored_rows = target_connection.execute(
            "SELECT employee_id, full_name FROM employees"
        ).fetchall()

        for stored_row in stored_rows:
            current_employee_id = str(stored_row["employee_id"]).strip()
            lookup_key = current_employee_id.lower()
            canonical_row = canonical_employees.get(lookup_key)
            if canonical_row is None:
                continue

            canonical_employee_id = canonical_row["employee_id"]
            canonical_full_name = canonical_row["full_name"]
            if (
                current_employee_id == canonical_employee_id
                and str(stored_row["full_name"]).strip() == canonical_full_name
            ):
                continue

            if current_employee_id == canonical_employee_id:
                target_connection.execute(
                    """
                    UPDATE employees
                    SET full_name = ?, updated_at = CURRENT_TIMESTAMP
                    WHERE employee_id = ?
                    """,
                    (canonical_full_name, current_employee_id),
                )
                continue

            existing_target = target_connection.execute(
                "SELECT employee_id FROM employees WHERE employee_id = ?",
                (canonical_employee_id,),
            ).fetchone()
            if existing_target is None:
                target_connection.execute(
                    """
                    INSERT INTO employees (
                        employee_id,
                        employee_code,
                        full_name,
                        is_active,
                        created_at,
                        updated_at
                    )
                    SELECT ?, employee_code, ?, is_active, created_at, CURRENT_TIMESTAMP
                    FROM employees
                    WHERE employee_id = ?
                    """,
                    (canonical_employee_id, canonical_full_name, current_employee_id),
                )
            else:
                target_connection.execute(
                    """
                    UPDATE employees
                    SET full_name = ?, updated_at = CURRENT_TIMESTAMP
                    WHERE employee_id = ?
                    """,
                    (canonical_full_name, canonical_employee_id),
                )
            target_connection.execute(
                "UPDATE face_embeddings SET employee_id = ? WHERE employee_id = ?",
                (canonical_employee_id, current_employee_id),
            )
            target_connection.execute(
                "UPDATE attendance_events SET employee_id = ? WHERE employee_id = ?",
                (canonical_employee_id, current_employee_id),
            )
            target_connection.execute(
                "DELETE FROM employees WHERE employee_id = ?",
                (current_employee_id,),
            )


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
        use_sface_if_available=FACE_MODEL_DIR.exists(),
    )

    repository = SQLiteFaceAttendanceRepository(config)
    engine = OpenCVFaceEngine(config)
    service = FaceAttendanceService(repository=repository, engine=engine, config=config)
    service.initialize()
    FACE_DATA_ROOT.mkdir(parents=True, exist_ok=True)
    FACE_CAPTURE_DIR.mkdir(parents=True, exist_ok=True)
    _copy_legacy_face_data(FACE_DATABASE_PATH)
    _sync_face_records_with_app_database(FACE_DATABASE_PATH)
    _service = service
    return _service


def enroll_employee(employee_id: str, full_name: str, image_b64: str) -> Dict[str, Any]:
    global _service
    _service = None  # Force reload config in case it changed without restart
    image_bytes = _decode_base64_image(image_b64)
    if image_bytes is None:
        return {"status": "error", "message": "Invalid face image data"}

    with open("debug_captured_face.jpg", "wb") as f:
        f.write(image_bytes)

    try:
        service = _get_service()
        # Temporarily relax engine criteria for this enroll action
        service.engine.config.detector_score_threshold = 0.50
        service.engine.config.min_face_size = 30
        service.engine.config.min_brightness = 10.0
        service.engine.config.max_brightness = 255.0
        service.engine.config.blur_threshold = 20.0
        
        result = service.enroll_employee(
            employee_id=employee_id,
            full_name=full_name,
            sample_images=[image_bytes],
        )
        result_dict = _to_plain_value(result)
        if result_dict.get("status") != "completed":
            sample_results = result_dict.get("sample_results") or []
            if sample_results:
                result_dict["reason"] = sample_results[0].get("reason", "Face enrollment failed.")
            return {"status": "error", "message": result_dict.get("reason", "No Face Detected. Ensure good lighting and proper distance.")}
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
        result = service.recognize(
            image_input=image_bytes,
            source=source,
            mark_attendance=mark_attendance,
        )
        return _to_plain_value(result)
    except Exception as exc:
        return {"status": "error", "reason": str(exc)}


def sync_employee_profile(
    current_employee_id: str,
    new_employee_id: str,
    full_name: str,
) -> Dict[str, Any]:
    try:
        service = _get_service()
        repository = service.repository
        with repository._connect() as connection:
            existing = connection.execute(
                "SELECT employee_id FROM employees WHERE employee_id = ?",
                (current_employee_id,),
            ).fetchone()

            if existing is None:
                repository.upsert_employee(new_employee_id, full_name)
                return {"status": "completed"}

            if current_employee_id == new_employee_id:
                connection.execute(
                    """
                    UPDATE employees
                    SET full_name = ?, updated_at = CURRENT_TIMESTAMP
                    WHERE employee_id = ?
                    """,
                    (full_name, current_employee_id),
                )
                return {"status": "completed"}

            target_exists = connection.execute(
                "SELECT employee_id FROM employees WHERE employee_id = ?",
                (new_employee_id,),
            ).fetchone()
            if target_exists is not None:
                return {
                    "status": "error",
                    "message": "Face data already exists for the new employee ID",
                }

            now = connection.execute("SELECT CURRENT_TIMESTAMP").fetchone()[0]
            connection.execute(
                """
                INSERT INTO employees (
                    employee_id,
                    employee_code,
                    full_name,
                    is_active,
                    created_at,
                    updated_at
                )
                SELECT ?, employee_code, ?, is_active, created_at, ?
                FROM employees
                WHERE employee_id = ?
                """,
                (new_employee_id, full_name, now, current_employee_id),
            )
            connection.execute(
                "UPDATE face_embeddings SET employee_id = ? WHERE employee_id = ?",
                (new_employee_id, current_employee_id),
            )
            connection.execute(
                "UPDATE attendance_events SET employee_id = ? WHERE employee_id = ?",
                (new_employee_id, current_employee_id),
            )
            connection.execute(
                "DELETE FROM employees WHERE employee_id = ?",
                (current_employee_id,),
            )
        return {"status": "completed"}
    except sqlite3.IntegrityError as exc:
        return {"status": "error", "message": str(exc)}
    except Exception as exc:
        return {"status": "error", "message": str(exc)}


def delete_employee_face(employee_id: str) -> Dict[str, Any]:
    try:
        service = _get_service()
        repository = service.repository
        with repository._connect() as connection:
            connection.execute("DELETE FROM employees WHERE employee_id = ?", (employee_id,))
        return {"status": "completed"}
    except Exception as exc:
        return {"status": "error", "message": str(exc)}
