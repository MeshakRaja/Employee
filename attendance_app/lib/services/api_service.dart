import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Use your live Render URL
  static const String baseUrl = "https://employeeattendance-8gup.onrender.com";

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/employees/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "employee_id": email,
          "password": password,
        }),
      ).timeout(const Duration(seconds: 60)); // Long timeout for Render's free tier

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        // Return the error message from your Flask backend
        return {"error": true, "message": "Login failed: ${response.statusCode}"};
      }
    } catch (e) {
      // Catch network errors or timeouts
      return {"error": true, "message": e.toString()};
    }
  }
}