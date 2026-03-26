import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/admin_page.dart';
import 'screens/dashboard_screen.dart';
import 'screens/mark_attendance_screen.dart';
import 'screens/attendance_history.dart';

void main() {
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Attendance System',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: LoginScreen(),
      routes: {
        '/admin': (context) => AdminPage(),
        '/dashboard': (context) => DashboardScreen(),
        '/mark_attendance': (context) => MarkAttendanceScreen(),
        '/attendance_history': (context) => AttendanceHistory(),
      },
    );
  }
}
