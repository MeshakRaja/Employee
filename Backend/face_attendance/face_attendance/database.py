from __future__ import annotations

import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any

import numpy as np

from .config import FaceModuleConfig


class SQLiteFaceAttendanceRepository:
    def __init__(self, config: FaceModuleConfig) -> None:
        self.config = config
        self.database_path = Path(config.database_path)

    def init_db(self) -> None:
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS employees (
                    employee_id TEXT PRIMARY KEY,
                    employee_code TEXT UNIQUE,
                    full_name TEXT NOT NULL,
                    is_active INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS face_embeddings (
                    embedding_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    employee_id TEXT NOT NULL,
                    sample_index INTEGER NOT NULL,
                    embedding BLOB NOT NULL,
                    detector_backend TEXT NOT NULL,
                    quality_score REAL NOT NULL,
                    image_path TEXT,
                    created_at TEXT NOT NULL,
                    UNIQUE(employee_id, sample_index),
                    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE
                );

                CREATE INDEX IF NOT EXISTS idx_face_embeddings_employee
                    ON face_embeddings(employee_id);

                CREATE TABLE IF NOT EXISTS attendance_settings (
                    settings_id INTEGER PRIMARY KEY CHECK (settings_id = 1),
                    duplicate_window_minutes INTEGER NOT NULL DEFAULT 5,
                    min_checkout_gap_minutes INTEGER NOT NULL DEFAULT 30,
                    match_threshold REAL NOT NULL DEFAULT 0.82,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS attendance_events (
                    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    employee_id TEXT NOT NULL,
                    event_date TEXT NOT NULL,
                    event_type TEXT NOT NULL CHECK (event_type IN ('check_in', 'check_out')),
                    confidence REAL NOT NULL,
                    similarity REAL NOT NULL,
                    captured_at TEXT NOT NULL,
                    source TEXT,
                    image_path TEXT,
                    created_at TEXT NOT NULL,
                    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE
                );

                CREATE INDEX IF NOT EXISTS idx_attendance_events_employee_date
                    ON attendance_events(employee_id, event_date, event_type);
                """
            )
            connection.execute(
                """
                INSERT OR IGNORE INTO attendance_settings (
                    settings_id,
                    duplicate_window_minutes,
                    min_checkout_gap_minutes,
                    match_threshold,
                    updated_at
                )
                VALUES (?, ?, ?, ?, ?)
                """,
                (
                    1,
                    self.config.duplicate_window_minutes,
                    self.config.min_checkout_gap_minutes,
                    self.config.match_threshold,
                    self._now(),
                ),
            )

    def upsert_employee(
        self,
        employee_id: str,
        full_name: str,
        employee_code: str | None = None,
        is_active: bool = True,
    ) -> None:
        now = self._now()
        with self._connect() as connection:
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
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(employee_id) DO UPDATE SET
                    employee_code = excluded.employee_code,
                    full_name = excluded.full_name,
                    is_active = excluded.is_active,
                    updated_at = excluded.updated_at
                """,
                (
                    employee_id,
                    employee_code,
                    full_name,
                    int(is_active),
                    now,
                    now,
                ),
            )

    def replace_embeddings(self, employee_id: str, embeddings: list[dict[str, Any]]) -> None:
        with self._connect() as connection:
            connection.execute(
                "DELETE FROM face_embeddings WHERE employee_id = ?",
                (employee_id,),
            )
            connection.executemany(
                """
                INSERT INTO face_embeddings (
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
                        employee_id,
                        item["sample_index"],
                        self._serialize_embedding(item["embedding"]),
                        item["detector_backend"],
                        item["quality_score"],
                        item.get("image_path"),
                        self._now(),
                    )
                    for item in embeddings
                ],
            )

    def get_all_embeddings(self) -> list[dict[str, Any]]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT
                    employees.employee_id,
                    employees.employee_code,
                    employees.full_name,
                    face_embeddings.sample_index,
                    face_embeddings.embedding,
                    face_embeddings.detector_backend,
                    face_embeddings.quality_score,
                    face_embeddings.image_path
                FROM face_embeddings
                INNER JOIN employees
                    ON employees.employee_id = face_embeddings.employee_id
                WHERE employees.is_active = 1
                ORDER BY employees.employee_id, face_embeddings.sample_index
                """
            ).fetchall()
        return [
            {
                "employee_id": row["employee_id"],
                "employee_code": row["employee_code"],
                "full_name": row["full_name"],
                "sample_index": row["sample_index"],
                "embedding": self._deserialize_embedding(row["embedding"]),
                "detector_backend": row["detector_backend"],
                "quality_score": row["quality_score"],
                "image_path": row["image_path"],
            }
            for row in rows
        ]

    def get_settings(self) -> dict[str, Any]:
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT
                    duplicate_window_minutes,
                    min_checkout_gap_minutes,
                    match_threshold,
                    updated_at
                FROM attendance_settings
                WHERE settings_id = 1
                """
            ).fetchone()
        if row is None:
            return {
                "duplicate_window_minutes": self.config.duplicate_window_minutes,
                "min_checkout_gap_minutes": self.config.min_checkout_gap_minutes,
                "match_threshold": self.config.match_threshold,
                "updated_at": self._now(),
            }
        return dict(row)

    def update_settings(
        self,
        duplicate_window_minutes: int | None = None,
        min_checkout_gap_minutes: int | None = None,
        match_threshold: float | None = None,
    ) -> None:
        current = self.get_settings()
        with self._connect() as connection:
            connection.execute(
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
                    duplicate_window_minutes
                    if duplicate_window_minutes is not None
                    else current["duplicate_window_minutes"],
                    min_checkout_gap_minutes
                    if min_checkout_gap_minutes is not None
                    else current["min_checkout_gap_minutes"],
                    match_threshold if match_threshold is not None else current["match_threshold"],
                    self._now(),
                ),
            )

    def get_daily_events(self, employee_id: str, event_date: str) -> list[dict[str, Any]]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT
                    event_id,
                    employee_id,
                    event_date,
                    event_type,
                    confidence,
                    similarity,
                    captured_at,
                    source,
                    image_path,
                    created_at
                FROM attendance_events
                WHERE employee_id = ? AND event_date = ?
                ORDER BY captured_at ASC
                """,
                (employee_id, event_date),
            ).fetchall()
        return [dict(row) for row in rows]

    def add_attendance_event(
        self,
        employee_id: str,
        event_date: str,
        event_type: str,
        confidence: float,
        similarity: float,
        captured_at: str,
        source: str | None = None,
        image_path: str | None = None,
    ) -> int:
        with self._connect() as connection:
            cursor = connection.execute(
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
                (
                    employee_id,
                    event_date,
                    event_type,
                    confidence,
                    similarity,
                    captured_at,
                    source,
                    image_path,
                    self._now(),
                ),
            )
            return int(cursor.lastrowid)

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        return connection

    @staticmethod
    def _serialize_embedding(embedding: np.ndarray) -> bytes:
        return np.asarray(embedding, dtype=np.float32).tobytes()

    @staticmethod
    def _deserialize_embedding(payload: bytes) -> np.ndarray:
        return np.frombuffer(payload, dtype=np.float32)

    @staticmethod
    def _now() -> str:
        return datetime.now().isoformat(timespec="seconds")
