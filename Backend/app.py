import os  # <--- Add this import at the top
from flask import Flask, jsonify
from flask_cors import CORS
from database import create_tables

from routes.student_routes import student_routes
from routes.admin_routes import admin_routes
from routes.attendance_routes import attendance_routes

app = Flask(__name__)
# Standard CORS setup is fine for development;
# for production, you might eventually restrict "origins" to your frontend URL
CORS(app, resources={r"/*": {"origins": "*"}})

# Initialize database tables
create_tables()

app.register_blueprint(student_routes)
app.register_blueprint(admin_routes)
app.register_blueprint(attendance_routes)

@app.route("/")
def home():
    return jsonify({
        "status": "success",
        "message": "Employee Attendance Backend is Live"
    })

if __name__ == "__main__":
    # Render provides the PORT as an environment variable.
    # If it's not found (like when running locally), it defaults to 5000.
    port = int(os.environ.get("PORT", 5000))

    # Switch debug=False for deployment to improve security and performance
    app.run(host='0.0.0.0', port=port, debug=False)