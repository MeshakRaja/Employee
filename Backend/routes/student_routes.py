from flask import Blueprint, request, jsonify
import sqlite3
import datetime

from database import DATABASE
from face_service import delete_employee_face, enroll_employee as enroll_face

student_bp = Blueprint("employee", __name__)

# -----------------------
# EMPLOYEE LOGIN
# -----------------------
@student_bp.route("/employees/login", methods=["POST"])
def employee_login():
    data = request.json
    employee_id = data.get("employee_id")
    password = data.get("password")

    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()

    c.execute("SELECT * FROM employees WHERE employee_id=? AND password=?", (employee_id, password))
    employee = c.fetchone()

    if employee:
        # store login notification
        now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        c.execute(
            "INSERT INTO notifications(employee_name, employee_id, department, date, message) VALUES (?,?,?,?,?)",
            (employee[1], employee[2], employee[3], now.split(" ")[0], f"Login at {now}")
        )
        conn.commit()
        conn.close()

        return jsonify({
            "status": "success",
            "employee": {
                "id": employee[0],
                "name": employee[1],
                "employee_id": employee[2],
                "department": employee[3]
            }
        })
    else:
        conn.close()
        return jsonify({
            "status": "failed",
            "message": "Invalid credentials"
        })


@student_bp.route("/employees/leave/apply", methods=["POST"])
def apply_leave():
    data = request.json
    employee_id = data.get("employee_id")
    leave_type = data.get("type", "Full Day")
    days = data.get("days")
    hours = data.get("hours")
    reason = data.get("reason", "")
    start_date = data.get("start_date")
    end_date = data.get("end_date") or start_date

    # basic validation
    if leave_type == "Hours":
        try:
            hours = float(hours)
        except (TypeError, ValueError):
            return jsonify({"status": "error", "message": "Hours must be provided for hourly permission"}), 400
        if hours <= 0:
            return jsonify({"status": "error", "message": "Hours must be greater than 0"}), 400
        days = 0
    else:
        try:
            days = float(days)
        except (TypeError, ValueError):
            return jsonify({"status": "error", "message": "Days must be provided"}), 400
        if days <= 0:
            return jsonify({"status": "error", "message": "Days must be greater than 0"}), 400
        hours = None

    month = datetime.datetime.now().strftime("%Y-%m")
    today = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")

    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    c.execute("SELECT name, department FROM employees WHERE employee_id=?", (employee_id,))
    emp = c.fetchone()
    if not emp:
        conn.close()
        return jsonify({"status": "error", "message": "Employee not found"}), 404

    c.execute(
        """
        INSERT INTO leave_requests(employee_id, employee_name, department, days, hours, type, reason, status, month, start_date, end_date, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (employee_id, emp[0], emp[1], days, hours, leave_type, reason, "Pending", month, start_date, end_date, today),
    )

    c.execute(
        "INSERT INTO notifications(employee_name, employee_id, department, date, message) VALUES (?,?,?,?,?)",
        (emp[0], employee_id, emp[1], today.split(" ")[0], f"Leave request: {leave_type} ({hours if leave_type=='Hours' else days})")
    )

    conn.commit()
    conn.close()
    return jsonify({"status": "success", "message": "Leave request submitted"})

# -----------------------
# ADD EMPLOYEE
# -----------------------
@student_bp.route("/employees/add", methods=["POST"])
def create_employee():
    data = request.json
    name = data.get("name")
    employee_id = data.get("employee_id")
    password = data.get("password")
    department = data.get("department")
    face_image = data.get("face_image")
    monthly_salary = data.get("monthly_salary", 12000.0)

    if not all([name, employee_id, password, department, face_image]):
        return jsonify({"message": "All fields including face_image are required"}), 400

    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()

    try:
        c.execute("""
        INSERT INTO employees (name, employee_id, department, password, monthly_salary)
        VALUES (?, ?, ?, ?, ?)
        """, (name, employee_id, department, password, monthly_salary))

        conn.commit()

        enroll_result = enroll_face(employee_id, name, face_image)
        if enroll_result.get("status") not in ("completed", "success"):
            c.execute("DELETE FROM employees WHERE employee_id=?", (employee_id,))
            conn.commit()
            conn.close()
            return jsonify({
                "message": enroll_result.get("reason")
                or enroll_result.get("message", "Face enrollment failed")
            }), 400

        conn.close()
        return jsonify({"message": "Employee added successfully"})
    except sqlite3.IntegrityError:
        conn.close()
        return jsonify({"message": "Employee ID already exists"}), 400
    except Exception as e:
        delete_employee_face(employee_id)
        conn.close()
        return jsonify({"message": str(e)}), 500

# -----------------------
# SALARY DETAILS
# -----------------------
@student_bp.route("/employees/salary/<employee_id>", methods=["GET"])
def get_employee_salary(employee_id):
    from datetime import datetime
    import calendar

    now = datetime.now()
    current_month = now.strftime("%Y-%m")
    current_year = now.strftime("%Y")

    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()

    # Get employee details
    c.execute("SELECT name, monthly_salary FROM employees WHERE employee_id=?", (employee_id,))
    emp = c.fetchone()
    if not emp:
        conn.close()
        return jsonify({"message": "Employee not found"})

    monthly_salary = emp[1]
    per_minute_rate = monthly_salary / (30 * 8 * 60)  # Assuming 30 days, 8 hours, 60 minutes

    # Get leave requests for current month
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

    # Calculate extra leaves (beyond 1 paid leave)
    extra_leaves = max(0, approved_leaves - 1)

    # Get late minutes for current month
    c.execute("""
    SELECT SUM(late_minutes) as total_late_minutes
    FROM attendance 
    WHERE employee_id=? AND strftime('%Y-%m', date)=?
    """, (employee_id, current_month))

    late_data = c.fetchone()
    total_late_minutes = late_data[0] or 0

    # Calculate deductions
    deduction_per_leave = monthly_salary / 30  # Daily rate
    deduction_per_half_day = deduction_per_leave / 2
    late_deduction = total_late_minutes * per_minute_rate

    extra_leave_deduction = extra_leaves * deduction_per_leave
    half_day_deduction = half_day_leaves * deduction_per_half_day

    total_deduction = extra_leave_deduction + half_day_deduction + late_deduction
    final_salary = monthly_salary - total_deduction

    # Check if salary record exists, if not create it
    c.execute("""
    INSERT OR REPLACE INTO salary_deductions 
    (employee_id, month, year, total_leaves, extra_leaves, half_day_leaves, late_minutes, 
     deduction_amount, final_salary, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        employee_id, current_month, current_year, total_leaves, extra_leaves, 
        half_day_leaves, total_late_minutes, total_deduction, final_salary, 
        datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    ))

    conn.commit()
    conn.close()

    return jsonify({
        "monthly_salary": monthly_salary,
        "paid_leave_allowed": 1,
        "total_leaves": total_leaves,
        "approved_leaves": approved_leaves,
        "extra_leaves": extra_leaves,
        "half_day_leaves": half_day_leaves,
        "late_minutes": total_late_minutes,
        "deduction_per_minute": per_minute_rate,
        "extra_leave_deduction": extra_leave_deduction,
        "half_day_deduction": half_day_deduction,
        "late_deduction": late_deduction,
        "total_deduction": total_deduction,
        "final_salary": final_salary
    })

# -----------------------
# NOTIFICATIONS
# -----------------------
@student_bp.route("/employees/notifications/<employee_id>", methods=["GET"])
def get_employee_notifications(employee_id):
    conn = sqlite3.connect(DATABASE)
    c = conn.cursor()
    c.execute("SELECT id, employee_name, employee_id, department, date, message FROM notifications WHERE employee_id=? ORDER BY id DESC", (employee_id,))
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

student_routes = student_bp
