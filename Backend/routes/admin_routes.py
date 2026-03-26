from flask import Blueprint, request, jsonify
import os
import sqlite3
from datetime import datetime

from database import DATABASE
from face_service import (
    delete_employee_face,
    enroll_employee as enroll_face,
    sync_employee_profile,
)

admin_bp = Blueprint("admin", __name__)

ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "admin123")

@admin_bp.route("/admin/login", methods=["POST"])
def admin_login():
    data = request.json
    password = data.get("password")

    if password == ADMIN_PASSWORD:
        return jsonify({"status": "success"})
    else:
        return jsonify({"status": "failed"})

@admin_bp.route("/admin/employees", methods=["GET"])
def get_employees():
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    c.execute("SELECT id, name, employee_id, department, monthly_salary FROM employees")
    employees = c.fetchall()
    conn.close()
    return jsonify([
        {
            "id": e[0],
            "name": e[1],
            "employee_id": e[2],
            "department": e[3],
            "monthly_salary": e[4],
        }
        for e in employees
    ])

@admin_bp.route("/admin/employees/<int:id>", methods=["PUT"])
def update_employee(id):
    data = request.json
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    c.execute("SELECT employee_id, name, monthly_salary FROM employees WHERE id=?", (id,))
    existing = c.fetchone()
    if not existing:
        conn.close()
        return jsonify({"message": "Employee not found"}), 404

    current_employee_id = existing[0]
    current_name = existing[1]
    current_salary = existing[2]

    c.execute(
        "SELECT id FROM employees WHERE employee_id=? AND id<>?",
        (data["employee_id"], id),
    )
    duplicate = c.fetchone()
    if duplicate:
        conn.close()
        return jsonify({"message": "Employee ID already exists"}), 400

    sync_applied = False
    if current_employee_id != data["employee_id"] or current_name != data["name"]:
        sync_result = sync_employee_profile(
            current_employee_id=current_employee_id,
            new_employee_id=data["employee_id"],
            full_name=data["name"],
        )
        if sync_result.get("status") not in ("completed", "success"):
            conn.close()
            return jsonify({"message": sync_result.get("message", "Failed to sync face data")}), 400
        sync_applied = True

    face_image = data.get("face_image")
    if face_image:
        enroll_result = enroll_face(data["employee_id"], data["name"], face_image)
        if enroll_result.get("status") not in ("completed", "success"):
            if sync_applied:
                sync_employee_profile(
                    current_employee_id=data["employee_id"],
                    new_employee_id=current_employee_id,
                    full_name=current_name,
                )
            conn.close()
            return jsonify({
                "message": enroll_result.get("reason")
                or enroll_result.get("message", "Face enrollment failed")
            }), 400

    try:
        c.execute("""
        UPDATE employees SET name=?, employee_id=?, department=?, password=?, monthly_salary=?
        WHERE id=?
        """, (
            data["name"],
            data["employee_id"],
            data["department"],
            data["password"],
            data.get("monthly_salary", current_salary if current_salary is not None else 12000.0),
            id,
        ))
        conn.commit()
        conn.close()
        return jsonify({"message": "Employee updated"})
    except Exception as exc:
        if sync_applied:
            sync_employee_profile(
                current_employee_id=data["employee_id"],
                new_employee_id=current_employee_id,
                full_name=current_name,
            )
        conn.close()
        return jsonify({"message": str(exc)}), 500

@admin_bp.route("/admin/employees/<int:id>", methods=["DELETE"])
def delete_employee(id):
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    c.execute("SELECT employee_id FROM employees WHERE id=?", (id,))
    employee = c.fetchone()
    if not employee:
        conn.close()
        return jsonify({"message": "Employee not found"}), 404

    c.execute("DELETE FROM employees WHERE id=?", (id,))
    conn.commit()
    conn.close()
    delete_employee_face(employee[0])
    return jsonify({"message": "Employee deleted"})

@admin_bp.route("/admin/notifications", methods=["GET"])
def get_notifications():
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    c.execute("SELECT id, employee_name, employee_id, department, date, message FROM notifications ORDER BY id DESC")
    notifications = c.fetchall()
    conn.close()
    return jsonify([
        {
            "id": n[0],
            "employee_name": n[1],
            "employee_id": n[2],
            "department": n[3],
            "date": n[4],
            "message": n[5]
        } for n in notifications
    ])

@admin_bp.route("/admin/attendance/today", methods=["GET"])
def get_today_attendance():
    today = datetime.now().strftime("%Y-%m-%d")
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    c.execute("""
        SELECT employee_id, name, department, date, login_time, logout_time, late_minutes
        FROM attendance
        WHERE date=?
        ORDER BY login_time ASC
    """, (today,))
    rows = c.fetchall()
    conn.close()

    def format_time(t):
        if not t:
            return None
        try:
            val = datetime.strptime(t, "%H:%M").strftime("%I:%M %p")
            return val.lstrip("0") if val.startswith("0") else val
        except Exception:
            return t

    def late_label(minutes):
        m = minutes or 0
        if m < 60:
            return f"{m} mins late" if m > 0 else "On time"
        h = m // 60
        rem = m % 60
        suffix = f" {rem} mins" if rem else ""
        hour_word = "hour" if h == 1 else "hours"
        return f"{h} {hour_word}{suffix} late"

    return jsonify([
        {
            "employee_id": r[0],
            "name": r[1],
            "department": r[2],
            "date": r[3],
            "login_time": format_time(r[4]),
            "logout_time": format_time(r[5]),
            "late_minutes": r[6],
            "late_label": late_label(r[6]),
        } for r in rows
    ])

@admin_bp.route("/admin/leaves", methods=["GET"])
def get_leaves():
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    c.execute("SELECT id, employee_id, employee_name, department, days, hours, type, reason, status, start_date, end_date, created_at FROM leave_requests ORDER BY id DESC")
    rows = c.fetchall()
    conn.close()
    return jsonify([
        {
            "id": r[0],
            "employee_id": r[1],
            "employee_name": r[2],
            "department": r[3],
            "days": r[4],
            "hours": r[5],
            "type": r[6],
            "reason": r[7],
            "status": r[8],
            "start_date": r[9],
            "end_date": r[10],
            "created_at": r[11],
        } for r in rows
    ])

@admin_bp.route("/admin/leaves/<int:leave_id>", methods=["POST"])
def update_leave(leave_id):
    action = request.json.get("action")  # Approve or Reject
    if action not in ["Approve", "Reject"]:
        return jsonify({"message": "Invalid action"}), 400

    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    c.execute("SELECT employee_id, employee_name, department FROM leave_requests WHERE id=?", (leave_id,))
    row = c.fetchone()
    if not row:
        conn.close()
        return jsonify({"message": "Leave not found"}), 404

    status_db = "Approved" if action == "Approve" else "Rejected"

    c.execute("UPDATE leave_requests SET status=? WHERE id=?", (status_db, leave_id))
    today = datetime.now().strftime("%Y-%m-%d")
    c.execute(
        "INSERT INTO notifications(employee_name, employee_id, department, date, message) VALUES (?,?,?,?,?)",
        (row[1], row[0], row[2], today, f"Leave {action.lower()} for {row[1]}"),
    )
    # notify employee
    c.execute(
        "INSERT INTO notifications(employee_name, employee_id, department, date, message) VALUES (?,?,?,?,?)",
        (row[1], row[0], row[2], today, f"Your leave was {action.lower()} by admin"),
    )
    conn.commit()
    conn.close()
    return jsonify({"message": f"Leave {action.lower()}"})

@admin_bp.route("/admin/salary/all", methods=["GET"])
def get_all_employee_salary():
    from datetime import datetime

    now = datetime.now()
    current_month = now.strftime("%Y-%m")
    current_year = now.strftime("%Y")

    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()

    # Get all employees
    c.execute("SELECT id, name, employee_id, department, monthly_salary FROM employees")
    employees = c.fetchall()

    salary_data = []
    for emp in employees:
        emp_id, name, employee_id, department, monthly_salary = emp

        per_minute_rate = monthly_salary / (30 * 8 * 60)

        # Get leave data
        c.execute("""
        SELECT SUM(days) as total_leaves, 
               SUM(CASE WHEN type='Half Day' THEN days ELSE 0 END) as half_days,
               SUM(CASE WHEN status='Approved' THEN days ELSE 0 END) as approved_leaves
        FROM leave_requests 
        WHERE employee_id=? AND month=? AND status='Approved'
        """, (employee_id, current_month))

        leave_data = c.fetchone()
        total_leaves = leave_data[0] or 0
        half_day_leaves = leave_data[1] or 0
        approved_leaves = leave_data[2] or 0
        extra_leaves = max(0, approved_leaves - 1)

        # Get late minutes
        c.execute("""
        SELECT SUM(late_minutes) as total_late_minutes
        FROM attendance 
        WHERE employee_id=? AND strftime('%Y-%m', date)=?
        """, (employee_id, current_month))

        late_data = c.fetchone()
        late_minutes = late_data[0] or 0

        # Calculate deductions
        deduction_per_leave = monthly_salary / 30
        deduction_per_half_day = deduction_per_leave / 2
        late_deduction = late_minutes * per_minute_rate

        extra_leave_deduction = extra_leaves * deduction_per_leave
        half_day_deduction = half_day_leaves * deduction_per_half_day

        deduction_amount = extra_leave_deduction + half_day_deduction + late_deduction
        final_salary = monthly_salary - deduction_amount

        # Insert or replace record
        c.execute("""
        INSERT OR REPLACE INTO salary_deductions 
        (employee_id, month, year, total_leaves, extra_leaves, half_day_leaves, late_minutes, 
         deduction_amount, final_salary, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            employee_id, current_month, current_year, total_leaves, extra_leaves, 
            half_day_leaves, late_minutes, deduction_amount, final_salary, 
            datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        ))

        salary_data.append({
            "employee_id": employee_id,
            "name": name,
            "department": department,
            "monthly_salary": monthly_salary,
            "total_leaves": total_leaves,
            "extra_leaves": extra_leaves,
            "half_day_leaves": half_day_leaves,
            "late_minutes": late_minutes,
            "deduction_amount": deduction_amount,
            "final_salary": final_salary
        })

    conn.commit()
    conn.close()
    return jsonify(salary_data)

admin_routes = admin_bp
