import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'admin_page.dart';

class AddEmployeePage extends StatefulWidget {
  final Map<String, dynamic>? employee;
  const AddEmployeePage({super.key, this.employee});

  @override
  _AddEmployeePageState createState() => _AddEmployeePageState();
}

class _AddEmployeePageState extends State<AddEmployeePage> {
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
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.employee != null) {
      nameController.text = widget.employee!['name'] ?? '';
      employeeIdController.text = widget.employee!['employee_id'] ?? '';
      departmentController.text = widget.employee!['department'] ?? '';
      salaryController.text = (widget.employee!['monthly_salary'] ?? '').toString();
    }
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (_isCameraLoading) return;
    setState(() {
      _isCameraLoading = true;
      _cameraErrorMessage = null;
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera detected.');
      }

      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();
      if (mounted) {
        setState(() {
          _cameraController = controller;
          _isCameraInitialized = true;
          _isCameraLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraErrorMessage = e.toString();
          _isCameraLoading = false;
        });
      }
    }
  }

  Future<void> _captureFace() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      final image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();
      setState(() => capturedFaceImage = base64Encode(bytes));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Face captured successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to capture face')),
      );
    }
  }

  Future<void> _submit() async {
    if (nameController.text.isEmpty ||
        employeeIdController.text.isEmpty ||
        departmentController.text.isEmpty ||
        (widget.employee == null && passwordController.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    if (widget.employee == null && capturedFaceImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture face image')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final isUpdate = widget.employee != null;
      final url = isUpdate
          ? '${AdminPage.baseUrl}/admin/employees/${widget.employee!['id']}'
          : '${AdminPage.baseUrl}/employees/add';

      final body = {
        'name': nameController.text,
        'employee_id': employeeIdController.text,
        'password': passwordController.text,
        'department': departmentController.text,
        'monthly_salary': double.tryParse(salaryController.text) ?? 12000.0,
      };

      if (capturedFaceImage != null) {
        body['face_image'] = capturedFaceImage!;
      }

      final response = await (isUpdate
          ? http.put(Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: json.encode(body))
          : http.post(Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: json.encode(body)));

      final data = json.decode(response.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Operation successful')),
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          Navigator.pop(context, true); // Return true to indicate success
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    nameController.dispose();
    employeeIdController.dispose();
    passwordController.dispose();
    departmentController.dispose();
    salaryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUpdate = widget.employee != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        title: Text(isUpdate ? 'Edit Employee' : 'Add Employee',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField(nameController, 'Full Name', Icons.person_outline),
            _buildTextField(employeeIdController, 'Employee ID', Icons.badge_outlined),
            _buildTextField(departmentController, 'Department', Icons.work_outline),
            if (!isUpdate) _buildTextField(passwordController, 'Password', Icons.lock_outline, isPassword: true),
            if (isUpdate) _buildTextField(passwordController, 'New Password (Optional)', Icons.lock_outline, isPassword: true),
            _buildTextField(salaryController, 'Monthly Salary', Icons.payments_outlined, isNumber: true),

            const SizedBox(height: 32),
            const Text('Biometric Enrollment',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            Container(
              height: 250,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: _isCameraInitialized && _cameraController != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: CameraPreview(_cameraController!),
                    )
                  : _isCameraLoading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF2DD4BF)))
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.videocam_off, color: Colors.white.withOpacity(0.3), size: 48),
                              const SizedBox(height: 16),
                              Text(_cameraErrorMessage ?? 'Camera not ready',
                                style: TextStyle(color: Colors.white.withOpacity(0.5))),
                              TextButton(onPressed: _initializeCamera, child: const Text('Retry'))
                            ],
                          ),
                        ),
            ),

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isCameraInitialized ? _captureFace : null,
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: Text(capturedFaceImage != null ? 'Retake Photo' : 'Capture Face'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                if (capturedFaceImage != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.check_circle, color: Color(0xFF10B981)),
                ]
              ],
            ),

            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 8,
                  shadowColor: const Color(0xFF0D9488).withOpacity(0.5),
                ),
                child: _isSubmitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(isUpdate ? 'UPDATE EMPLOYEE' : 'REGISTER EMPLOYEE',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon,
      {bool isPassword = false, bool isNumber = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
          prefixIcon: Icon(icon, color: const Color(0xFF2DD4BF)),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF2DD4BF)),
          ),
        ),
      ),
    );
  }
}
