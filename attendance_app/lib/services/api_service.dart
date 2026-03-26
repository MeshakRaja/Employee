import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {

  static const baseUrl = "http://192.168.31.227:5000";

  static Future login(email,password) async {

    var response = await http.post(

      Uri.parse("$baseUrl/student/login"),

      headers: {"Content-Type":"application/json"},

      body: jsonEncode({

        "email":email,
        "password":password

      }),

    );

    return jsonDecode(response.body);
  }

}