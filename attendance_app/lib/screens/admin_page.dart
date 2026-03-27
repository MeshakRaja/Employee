import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:camera/camera.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  static const String baseUrl = "https://employeeattendance-8gup.onrender.com";

  @override
  _AdminPageState createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<Map<String, dynamic>> notifications = [];
  List<Map<String, dynamic>> attendanceToday = [];
  List<Map<String, dynamic>> employees = [];
  List<Map<String, dynamic>> leaveRequests = [];
  List<Map<String, dynamic>> salaryData = [];

  bool notificationsLoading = false;
  String notificationsError = '';
  bool attendanceLoading = false;
  String attendanceError = '';
  bool leaveLoading = false;
  String leaveError = '';
  bool salaryLoading = false;
  String salaryError = '';
  bool isLoading = true;

  final nameController = TextEditingController();
  final employeeIdController = TextEditingController();
  final passwordController = TextEditingController();
  final departmentController = TextEditingController();
  final salaryController = TextEditingController();
  String? capturedFaceImage;

  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isCameraLoading = false;
  String? _cameraErrorMessage;

  @override
  void initState() {
    super.initState();
    fetchEmployees();
    fetchNotifications();
    fetchTodayAttendance();
    fetchLeaveRequests();
    fetchSalaryData();
  }

  // Camera helpers
  Future<void> _initializeCamera() async {
    if (_isCameraLoading) return;

    _isCameraLoading = true;
    await _disposeCamera();
    if (mounted) {
      setState(() => _cameraErrorMessage = null);
    } else {
      _cameraErrorMessage = null;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError(
          'No camera detected. Connect a webcam or allow camera access in the browser.',
        );
      }

      final orderedCameras = <CameraDescription>[
        ...cameras.where(
          (camera) => camera.lensDirection == CameraLensDirection.front,
        ),
        ...cameras.where(
          (camera) => camera.lensDirection != CameraLensDirection.front,
        ),
      ];

      Object? lastError;
      for (final camera in orderedCameras) {
        final controller = CameraController(
          camera,
          ResolutionPreset.high,
          enableAudio: false,
        );

        try {
          await controller.initialize();

          if (!mounted) {
            await controller.dispose();
            return;
          }

          setState(() {
            _cameraController = controller;
            _isCameraInitialized = true;
            _cameraErrorMessage = null;
          });
          return;
        } catch (error) {
          lastError = error;
          await controller.dispose();
        }
      }

      throw StateError(_friendlyCameraError(lastError));
    } catch (error) {
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _cameraErrorMessage = _friendlyCameraError(error);
        });
      } else {
        _isCameraInitialized = false;
        _cameraErrorMessage = _friendlyCameraError(error);
      }
    } finally {
      _isCameraLoading = false;
    }
  }

  Future<void> _disposeCamera() async {
    final controller = _cameraController;
    _cameraController = null;

    if (mounted) {
      setState(() => _isCameraInitialized = false);
    } else {
      _isCameraInitialized = false;
    }

    await controller?.dispose();
  }

  String _friendlyCameraError(Object? error) {
    final message = error?.toString() ?? '';
    if (message.contains('NotAllowedError') ||
        message.contains('permission') ||
        message.contains('Permission')) {
      return 'Camera permission was denied. Allow camera access in Chrome and try again.';
    }
    if (message.contains('NotFoundError') ||
        message.contains('No camera detected')) {
      return 'No camera was found. Connect a webcam or check browser camera access.';
    }
    if (message.contains('NotReadableError')) {
      return 'The camera is already being used by another app or browser tab.';
    }
    return 'Unable to start the camera. Close other camera apps and try again.';
  }

  Future<void> _captureFace() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      final image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();
      setState(() => capturedFaceImage = base64Encode(bytes));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Face captured successfully')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to capture face')));
    }
  }

  // Data calls (logic unchanged)
  Future<void> fetchEmployees() async {
    try {
      final response = await http.get(
        Uri.parse('${AdminPage.baseUrl}/admin/employees'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        setState(() {
          employees = data.map((e) => e as Map<String, dynamic>).toList();
          isLoading = false;
        });
      }
    } catch (_) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load employees')));
    }
  }

  Future<void> _updateLeave(int id, String action) async {
    try {
      await http.post(
        Uri.parse('${AdminPage.baseUrl}/admin/leaves/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'action': action}),
      );
      fetchLeaveRequests();
    } catch (_) {}
  }

  Future<void> addEmployee() async {
    if (capturedFaceImage == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Please capture face image')));
      return;
    }
    try {
      final response = await http.post(
        Uri.parse('${AdminPage.baseUrl}/employees/add'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': nameController.text,
          'employee_id': employeeIdController.text,
          'password': passwordController.text,
          'department': departmentController.text,
          'monthly_salary': double.tryParse(salaryController.text) ?? 12000.0,
          'face_image': capturedFaceImage,
        }),
      );
      final data = json.decode(response.body);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(data['message'])));
      if ((data['message'] ?? '').contains('Employee added')) {
        clearFields();
        fetchEmployees();
      }
    } catch (_) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Connection error')));
    }
  }

  Future<void> updateEmployee(int id) async {
    try {
      final Map<String, dynamic> body = {
        'name': nameController.text,
        'employee_id': employeeIdController.text,
        'password': passwordController.text,
        'department': departmentController.text,
        'monthly_salary': double.tryParse(salaryController.text) ?? 12000.0,
      };
      if (capturedFaceImage != null) {
        body['face_image'] = capturedFaceImage;
      }
      final response = await http.put(
        Uri.parse('${AdminPage.baseUrl}/admin/employees/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      final data = json.decode(response.body);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(data['message'])));
      if ((data['message'] ?? '').contains('Employee updated')) {
        clearFields();
        fetchEmployees();
      }
    } catch (_) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Connection error')));
    }
  }

  Future<void> deleteEmployee(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('${AdminPage.baseUrl}/admin/employees/$id'),
      );
      final data = json.decode(response.body);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(data['message'])));
      fetchEmployees();
    } catch (_) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Connection error')));
    }
  }

  Future<void> fetchNotifications() async {
    setState(() {
      notificationsLoading = true;
      notificationsError = '';
    });
    try {
      final response = await http.get(
        Uri.parse('${AdminPage.baseUrl}/admin/notifications'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        setState(
          () => notifications = data
              .map((e) => e as Map<String, dynamic>)
              .toList(),
        );
      } else {
        setState(() => notificationsError = 'Failed to load notifications');
      }
    } catch (_) {
      setState(() => notificationsError = 'Connection error');
    }
    setState(() => notificationsLoading = false);
  }

  Future<void> fetchTodayAttendance() async {
    setState(() {
      attendanceLoading = true;
      attendanceError = '';
    });
    try {
      final response = await http.get(
        Uri.parse('${AdminPage.baseUrl}/admin/attendance/today'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        setState(
          () => attendanceToday = data
              .map((e) => e as Map<String, dynamic>)
              .toList(),
        );
      } else {
        setState(() => attendanceError = 'Failed to load attendance');
      }
    } catch (_) {
      setState(() => attendanceError = 'Connection error');
    }
    setState(() => attendanceLoading = false);
  }

  Future<void> fetchLeaveRequests() async {
    setState(() {
      leaveLoading = true;
      leaveError = '';
    });
    try {
      final res = await http.get(
        Uri.parse('${AdminPage.baseUrl}/admin/leaves'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as List;
        setState(
          () => leaveRequests = data
              .map((e) => e as Map<String, dynamic>)
              .toList(),
        );
      } else {
        setState(() => leaveError = 'Failed to load leave requests');
      }
    } catch (_) {
      setState(() => leaveError = 'Connection error');
    }
    setState(() => leaveLoading = false);
  }

  Future<void> fetchSalaryData() async {
    setState(() {
      salaryLoading = true;
      salaryError = '';
    });
    try {
      final response = await http.get(
        Uri.parse('${AdminPage.baseUrl}/admin/salary/all'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        setState(
          () =>
              salaryData = data.map((e) => e as Map<String, dynamic>).toList(),
        );
      } else {
        setState(() => salaryError = 'Failed to load salary data');
      }
    } catch (_) {
      setState(() => salaryError = 'Connection error');
    }
    setState(() => salaryLoading = false);
  }

  void clearFields() {
    nameController.clear();
    employeeIdController.clear();
    passwordController.clear();
    departmentController.clear();
    salaryController.clear();
    capturedFaceImage = null;
  }

  void _showNotifications() {
    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<http.Response>(
          future: http.get(Uri.parse('${AdminPage.baseUrl}/admin/notifications')),
          builder: (context, snapshot) {
            bool isLoading = snapshot.connectionState == ConnectionState.waiting;
            List localNotifs = [];
            String localError = '';

            if (snapshot.hasError) {
              localError = 'Connection error';
            } else if (snapshot.hasData) {
              final response = snapshot.data!;
              if (response.statusCode == 200) {
                localNotifs = json.decode(response.body) as List;
              } else {
                localError = 'Failed to load notifications';
              }
            }

            return AlertDialog(
              title: const Text('Employee Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              content: isLoading
                  ? const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator(color: Colors.teal)),
                    )
                  : localError.isNotEmpty
                  ? Text(localError, style: const TextStyle(color: Colors.redAccent))
                  : localNotifs.isEmpty
                  ? const Text('No new notifications from employees.', style: TextStyle(color: Colors.grey))
                  : SizedBox(
                      width: 400,
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: localNotifs.length,
                        separatorBuilder: (context, _) => const Divider(),
                        itemBuilder: (context, idx) {
                          final n = localNotifs[idx];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.teal.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.notifications_active, color: Colors.teal),
                            ),
                            title: Text(
                              n['employee_name'] ?? 'Unknown Employee',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(
                                '${n['message']}\n${n['date'] ?? ''}',
                                style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade700, height: 1.4),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(color: Colors.teal)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Drawer _buildDrawer(BuildContext context) {
    Widget item(IconData icon, String title, VoidCallback onTap) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        leading: Icon(icon, color: Colors.white70, size: 22),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        hoverColor: Colors.white.withOpacity(0.05),
        onTap: onTap,
      );
    }

    return Drawer(
      backgroundColor: const Color(0xFF0F172A),
      elevation: 0,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2DD4BF), Color(0xFF0D9488)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0D9488).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Administrator",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Workspace Center",
                        style: TextStyle(
                          color: Colors.blueGrey.shade300,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Divider(
                color: Colors.white.withOpacity(0.1),
                thickness: 1,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  item(
                    Icons.dashboard_rounded,
                    "Dashboard",
                    () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 4),
                  item(
                    Icons.people_alt_rounded,
                    "Employees",
                    () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 4),
                  item(
                    Icons.fact_check_rounded,
                    "Attendance",
                    () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 4),
                  item(
                    Icons.event_note_rounded,
                    "Leave Requests",
                    () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 4),
                  item(
                    Icons.payments_rounded,
                    "Salary & Payroll",
                    () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Divider(
                color: Colors.white.withOpacity(0.1),
                thickness: 1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: item(
                Icons.logout_rounded,
                "Secure Logout",
                () => Navigator.pushReplacementNamed(context, '/'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> showEmployeeDialog({Map<String, dynamic>? employee}) async {
    if (employee != null) {
      nameController.text = employee['name'];
      employeeIdController.text = employee['employee_id'];
      departmentController.text = employee['department'];
      passwordController.text = '';
      salaryController.text = (employee['monthly_salary'] ?? '').toString();
      capturedFaceImage = null;
    } else {
      clearFields();
    }

    await _initializeCamera();

    if (!mounted) return;

    try {
      await showDialog(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setState) => AlertDialog(
            title: Text(employee == null ? 'Add Employee' : 'Edit Employee'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  TextField(
                    controller: passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    obscureText: true,
                  ),
                  TextField(
                    controller: departmentController,
                    decoration: InputDecoration(
                      labelText: 'Department',
                      prefixIcon: Icon(Icons.work_outline),
                    ),
                  ),
                  TextField(
                    controller: employeeIdController,
                    decoration: InputDecoration(
                      labelText: 'Employee ID',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  TextField(
                    controller: salaryController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Salary',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Face Capture',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10),
                  Container(
                    height: 150,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _isCameraInitialized && _cameraController != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CameraPreview(_cameraController!),
                          )
                        : _isCameraLoading
                        ? Center(child: CircularProgressIndicator())
                        : _cameraErrorMessage != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.videocam_off,
                                    color: Colors.redAccent,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    _cameraErrorMessage!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  SizedBox(height: 10),
                                  TextButton(
                                    onPressed: _initializeCamera,
                                    child: Text('Retry Camera'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              'Camera not ready',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                  ),
                  SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _isCameraInitialized
                        ? _captureFace
                        : _initializeCamera,
                    icon: Icon(Icons.camera_alt),
                    label: Text(
                      _isCameraInitialized
                          ? (capturedFaceImage != null
                                ? 'Recapture Face'
                                : 'Capture Face')
                          : 'Start Camera',
                    ),
                  ),
                  if (capturedFaceImage != null)
                    Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Face captured',
                        style: TextStyle(color: Colors.green),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (employee == null) {
                    await addEmployee();
                  } else {
                    await updateEmployee(employee['id']);
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                },
                child: Text(employee == null ? 'Add' : 'Update'),
              ),
            ],
          ),
        ),
      );
    } finally {
      await _disposeCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentCount = attendanceToday.length;
    final totalEmployees = employees.length;
    final pendingLeaves = leaveRequests
        .where((lr) => (lr['status'] ?? '') == 'Pending')
        .length;
    final absent = totalEmployees - presentCount;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      drawer: _buildDrawer(context),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: const Color(0xFF0B1120).withOpacity(0.8)),
          ),
        ),
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 24,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.notifications_none_rounded),
              color: Colors.white,
              onPressed: _showNotifications,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0, left: 8),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF2DD4BF), Color(0xFF0D9488)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0D9488).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.transparent,
                child: Icon(Icons.person, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B1120), Color(0xFF0F172A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Overview",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _SummaryGrid(
                  items: [
                    SummaryItem(
                      title: "Total Staff",
                      value: "$totalEmployees",
                      icon: Icons.groups_rounded,
                      color: const Color(0xFF3B82F6),
                    ),
                    SummaryItem(
                      title: "Present Today",
                      value: "$presentCount",
                      icon: Icons.how_to_reg_rounded,
                      color: const Color(0xFF10B981),
                    ),
                    SummaryItem(
                      title: "Absent Today",
                      value: "$absent",
                      icon: Icons.person_off_rounded,
                      color: const Color(0xFFF43F5E),
                    ),
                    SummaryItem(
                      title: "Pending Leaves",
                      value: "$pendingLeaves",
                      icon: Icons.pending_actions_rounded,
                      color: const Color(0xFFF59E0B),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                _SectionCard(
                  title: "Team Members",
                  action: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => showEmployeeDialog(),
                    icon: const Icon(Icons.person_add_rounded, size: 20),
                    label: const Text(
                      "Add Member",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  child: isLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : employees.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'No team members registered yet',
                              style: TextStyle(
                                color: Colors.blueGrey.shade300,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: employees.map((employee) {
                            return _EmployeeTile(
                              name: employee['name'],
                              id: employee['employee_id'],
                              department: employee['department'],
                              salary:
                                  "₹${(employee['monthly_salary'] ?? '12000')}",
                              onEdit: () =>
                                  showEmployeeDialog(employee: employee),
                              onDelete: () => deleteEmployee(employee['id']),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 24),
                _SectionCard(
                  title: "Today's Attendance",
                  child: attendanceLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : attendanceError.isNotEmpty
                      ? Center(
                          child: Text(
                            attendanceError,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        )
                      : attendanceToday.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'No check-ins recorded today',
                              style: TextStyle(
                                color: Colors.blueGrey.shade300,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: attendanceToday.map((a) {
                            final lateLabel =
                                a['late_label'] ?? '${a['late_minutes']}m';
                            final lateColor = (a['late_minutes'] ?? 0) > 0
                                ? const Color(0xFFF43F5E)
                                : const Color(0xFF10B981);
                            return _InfoTile(
                              title: a['name'],
                              subtitle:
                                  'ID: ${a['employee_id']} • ${a['department']}\nIn: ${a['login_time'] ?? '-'}  Out: ${a['logout_time'] ?? '-'}',
                              badge: lateLabel,
                              badgeColor: lateColor,
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 24),
                _SectionCard(
                  title: 'Leave Requests',
                  child: leaveLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : leaveError.isNotEmpty
                      ? Center(
                          child: Text(
                            leaveError,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        )
                      : leaveRequests.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'No pending leave requests',
                              style: TextStyle(
                                color: Colors.blueGrey.shade300,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: leaveRequests.map((lr) {
                            final isPending = (lr['status'] ?? '') == 'Pending';
                            final dateLabel =
                                (lr['end_date'] ?? lr['start_date']) !=
                                    lr['start_date']
                                ? '${lr['start_date']} - ${lr['end_date']}'
                                : '${lr['start_date'] ?? '-'}';
                            final duration = lr['hours'] != null
                                ? '${lr['hours']} hrs'
                                : '${lr['days']} d';
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.05),
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${lr['employee_name']}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    if (!isPending)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: lr['status'] == 'Approved'
                                              ? Colors.green.withOpacity(0.2)
                                              : Colors.orange.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: lr['status'] == 'Approved'
                                                ? Colors.green.withOpacity(0.5)
                                                : Colors.orange.withOpacity(
                                                    0.5,
                                                  ),
                                          ),
                                        ),
                                        child: Text(
                                          lr['status'],
                                          style: TextStyle(
                                            color: lr['status'] == 'Approved'
                                                ? Colors.greenAccent
                                                : Colors.orangeAccent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    'ID: ${lr['employee_id']} • ${lr['department']}\n'
                                    'Type: ${lr['type']}  • $duration\n'
                                    'Date: $dateLabel\n'
                                    'Reason: ${lr['reason'] ?? ''}',
                                    style: TextStyle(
                                      color: Colors.blueGrey.shade200,
                                      height: 1.5,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                trailing: isPending
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _ActionChip(
                                            icon: Icons.check_rounded,
                                            color: const Color(0xFF10B981),
                                            onTap: () => _updateLeave(
                                              lr['id'],
                                              'Approve',
                                            ),
                                          ),
                                          _ActionChip(
                                            icon: Icons.close_rounded,
                                            color: const Color(0xFFF43F5E),
                                            onTap: () => _updateLeave(
                                              lr['id'],
                                              'Reject',
                                            ),
                                          ),
                                        ],
                                      )
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 24),
                _SectionCard(
                  title: 'Salary Monitoring',
                  child: salaryLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : salaryError.isNotEmpty
                      ? Center(
                          child: Text(
                            salaryError,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        )
                      : salaryData.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'No salary data available',
                              style: TextStyle(
                                color: Colors.blueGrey.shade300,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: salaryData.map((s) {
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.05),
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                title: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${s['name']}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      '₹${s['final_salary'].toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    'ID: ${s['employee_id']} • Dept: ${s['department']}\n'
                                    'Base: ₹${s['monthly_salary']} • Late: ${s['late_minutes']}m • Leaves: ${s['total_leaves']}',
                                    style: TextStyle(
                                      color: Colors.blueGrey.shade300,
                                      height: 1.4,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    employeeIdController.dispose();
    passwordController.dispose();
    departmentController.dispose();
    salaryController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? action;
  const _SectionCard({required this.title, required this.child, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    if (action != null) action!,
                  ],
                ),
                const SizedBox(height: 16),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  final String name;
  final String id;
  final String department;
  final String salary;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _EmployeeTile({
    required this.name,
    required this.id,
    required this.department,
    required this.salary,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person, color: Color(0xFF60A5FA)),
        ),
        title: Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Text(
            'ID: $id • $department\nSalary: $salary',
            style: TextStyle(
              color: Colors.blueGrey.shade300,
              height: 1.4,
              fontSize: 13,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Color(0xFF2DD4BF)),
              onPressed: onEdit,
              tooltip: 'Edit',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color(0xFFF43F5E)),
              onPressed: onDelete,
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final List<SummaryItem> items;
  const _SummaryGrid({required this.items});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 650;
        final crossAxis = isWide ? 4 : 2;
        return GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxis,
          shrinkWrap: true,
          childAspectRatio: isWide ? 1.8 : 1.6,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: items.map((i) => _SummaryCard(item: i)).toList(),
        );
      },
    );
  }
}

class SummaryItem {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  SummaryItem({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _SummaryCard extends StatefulWidget {
  final SummaryItem item;
  const _SummaryCard({required this.item});

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _isHovering ? -6.0 : 0.0, 0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isHovering
                ? [
                    widget.item.color.withOpacity(0.35),
                    widget.item.color.withOpacity(0.08)
                  ]
                : [
                    widget.item.color.withOpacity(0.2),
                    widget.item.color.withOpacity(0.02)
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isHovering
                ? widget.item.color.withOpacity(0.6)
                : widget.item.color.withOpacity(0.2),
            width: _isHovering ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovering
                  ? widget.item.color.withOpacity(0.3)
                  : Colors.black.withOpacity(0.1),
              blurRadius: _isHovering ? 16 : 10,
              offset: Offset(0, _isHovering ? 8 : 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.item.color.withOpacity(_isHovering ? 0.25 : 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(widget.item.icon, color: widget.item.color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.item.title,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.item.value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  const _InfoTile({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Text(
            subtitle,
            style: TextStyle(
              color: Colors.blueGrey.shade300,
              height: 1.4,
              fontSize: 13,
            ),
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: badgeColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: badgeColor.withOpacity(0.3)),
          ),
          child: Text(
            badge,
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionChip({
    required this.icon,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}
