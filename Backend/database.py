import sqlite3
from pathlib import Path

DATABASE = str(Path(__file__).resolve().parent / "students.db")

def get_db():
    conn = sqlite3.connect(DATABASE)
    conn.row_factory = sqlite3.Row
    return conn


def create_tables():
    conn = get_db()
    cursor = conn.cursor()

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS employees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        employee_id TEXT UNIQUE NOT NULL,
        department TEXT NOT NULL,
        password TEXT NOT NULL,
        monthly_salary REAL DEFAULT 12000.0
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id TEXT NOT NULL,
        name TEXT NOT NULL,
        department TEXT NOT NULL,
        date TEXT NOT NULL,
        login_time TEXT NOT NULL,
        logout_time TEXT,
        late_minutes INTEGER DEFAULT 0
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_name TEXT NOT NULL,
        employee_id TEXT NOT NULL,
        department TEXT NOT NULL,
        date TEXT NOT NULL,
        message TEXT NOT NULL
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS leave_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id TEXT NOT NULL,
        employee_name TEXT NOT NULL,
        department TEXT NOT NULL,
        days REAL,
        hours REAL,
        type TEXT NOT NULL,
        reason TEXT,
        status TEXT NOT NULL,
        month TEXT NOT NULL,
        start_date TEXT,
        end_date TEXT,
        created_at TEXT NOT NULL
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS salary_deductions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id TEXT NOT NULL,
        month TEXT NOT NULL,
        year TEXT NOT NULL,
        total_leaves REAL DEFAULT 0,
        extra_leaves REAL DEFAULT 0,
        half_day_leaves REAL DEFAULT 0,
        late_minutes INTEGER DEFAULT 0,
        deduction_amount REAL DEFAULT 0,
        final_salary REAL DEFAULT 0,
        created_at TEXT NOT NULL,
        UNIQUE(employee_id, month, year)
    )
    """)

    # ensure new columns exist for legacy databases
    try:
        cursor.execute("ALTER TABLE leave_requests ADD COLUMN hours REAL")
    except Exception:
        pass
    try:
        cursor.execute("ALTER TABLE leave_requests ADD COLUMN start_date TEXT")
    except Exception:
        pass
    try:
        cursor.execute("ALTER TABLE leave_requests ADD COLUMN end_date TEXT")
    except Exception:
        pass

    conn.commit()
    conn.close()
