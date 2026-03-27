import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class MarkAttendanceScreen extends StatefulWidget {
  const MarkAttendanceScreen({super.key});

  @override
  _MarkAttendanceScreenState createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  CameraController? _cameraController;
  bool isLoading = false;
  bool isLocationValid = false;
  String locationMessage = "Scanning for geo-fenced office...";
  String? _capturedImageBase64;
  StreamSubscription<Position>? _positionStreamSubscription;

  // Use the Render URL instead of localhost
  final String baseUrl = "https://employeeattendance-8gup.onrender.com";

  static const double targetLat = 8.749176;
  static const double targetLng = 77.703413;
  static const double maxAllowedDistance = 50.0; // Allowed range: 40-50 meters

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _checkLocationPermission();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _checkLocationPermission() async {
    var status = await Permission.location.status;
    if (!status.isGranted) status = await Permission.location.request();
    
    if (status.isGranted) {
      getCurrentLocation();
    } else if (mounted) {
      setState(() {
        locationMessage = "Location permission denied";
        isLocationValid = false;
      });
    }
  }

  void getCurrentLocation() async {
    setState(() => locationMessage = "Acquiring GPS Signal...");
    
    // 1. Fetch position immediately to avoid waiting indefinitely
    try {
      Position initialPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      validateLocation(initialPos);
    } catch (_) {}
    
    // 2. Track real-time stream without a distance filter freezing updates
    final LocationSettings locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.best,
    );
    
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      validateLocation(position);
    }, onError: (e) {
      if (mounted) {
        setState(() => locationMessage = "Failed to track location");
      }
    });
  }

  double checkDistance(Position position) {
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      targetLat,
      targetLng,
    );
  }

  void validateLocation(Position position) {
    if (!mounted) return;
    
    double distance = checkDistance(position);

    // If the GPS accuracy is extremely bad (> 150m), block authentication and explicitly ask to Turn On Wi-Fi
    if (position.accuracy > 150.0) {
      setState(() {
        locationMessage = "Locating... Turn ON Wi-Fi for better GPS!";
        isLocationValid = false;
      });
      return; 
    }

    // We removed the strict '40m' accuracy block. 
    // Now, even if accuracy is 128m, it will check if you are mathematically inside the 50m zone.
    setState(() {
      if (distance <= maxAllowedDistance) {
        locationMessage = "In Range (${distance.toStringAsFixed(0)}m)";
        isLocationValid = true;
      } else {
        locationMessage = "Out of Range (${distance.toStringAsFixed(0)}m)";
        isLocationValid = false;
      }
    });
  }

  Future<void> _captureFace() async {
    if (!isLocationValid)
      return _showError('You must be within the geofence to capture');
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return _showError('Camera not available');
    try {
      final image = await _cameraController!.takePicture();
      try {
        await _cameraController!.pausePreview();
      } catch (_) {}
      final bytes = await image.readAsBytes();
      setState(() => _capturedImageBase64 = base64Encode(bytes));
    } catch (e) {
      _showError('Failed to capture frame');
    }
  }

  Future<void> _retakeFace() async {
    setState(() {
      _capturedImageBase64 = null;
      isLoading = true;
    });
    try {
      if (_cameraController != null) {
        await _cameraController!.dispose();
        _cameraController = null;
      }
      await _initializeCamera();
    } catch (_) {}
    
    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Future<void> markAttendance(BuildContext context, String employeeId) async {
    if (!isLocationValid) return _showError('Outside geofence zone');
    if (_capturedImageBase64 == null)
      return _showError('Please capture your biometrics first');
    setState(() => isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/attendance/mark'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'employee_id': employeeId,
          'face_image': _capturedImageBase64,
        }),
      );
      final data = json.decode(response.body);
      final isSuccess = data['message'].toString().toLowerCase().contains(
        'successfully',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: isSuccess ? Colors.green : Colors.redAccent,
          content: Text(
            data['message'],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
      if (isSuccess && mounted) Navigator.pop(context);
    } catch (e) {
      _showError('Connection error resolving request.');
    }
    if (mounted) setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final employee =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Biometric Sync',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // Full Screen Camera Background
          Positioned.fill(
            child: _capturedImageBase64 != null
                ? Image.memory(
                    base64Decode(_capturedImageBase64!),
                    fit: BoxFit.cover,
                  )
                : (_cameraController != null &&
                      _cameraController!.value.isInitialized)
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _cameraController!.value.previewSize?.height,
                      height: _cameraController!.value.previewSize?.width,
                      child: CameraPreview(_cameraController!),
                    ),
                  )
                : const Center(
                    child: CircularProgressIndicator(color: Colors.cyanAccent),
                  ),
          ),

          // Camera targeting overlay
          Positioned.fill(
            child: Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _capturedImageBase64 != null
                        ? Colors.green
                        : Colors.white.withOpacity(0.5),
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: _capturedImageBase64 == null
                    ? const Icon(
                        Icons.face_retouching_natural,
                        color: Colors.white54,
                        size: 80,
                      )
                    : const Center(
                        child: Icon(
                          Icons.check_circle,
                          color: Colors.greenAccent,
                          size: 80,
                        ),
                      ),
              ),
            ),
          ),

          // Bottom Controls (Glassmorphism)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 32,
                    bottom: 40,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF09090B).withOpacity(0.85),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(40),
                      topRight: Radius.circular(40),
                    ),
                    border: Border(
                      top: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Location Pin Indicator
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isLocationValid
                              ? Colors.green.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isLocationValid
                                ? Colors.green.withOpacity(0.3)
                                : Colors.red.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isLocationValid
                                  ? Icons.my_location_rounded
                                  : Icons.location_off_rounded,
                              color: isLocationValid
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              locationMessage,
                              style: TextStyle(
                                color: isLocationValid
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white12,
                            ),
                            child: const Icon(
                              Icons.badge,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                employee['name'],
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                '${employee['department']} • ID: ${employee['employee_id']}',
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: ElevatedButton(
                              onPressed:
                                  (isLoading ||
                                      !isLocationValid ||
                                      _cameraController == null)
                                  ? null
                                  : (_capturedImageBase64 == null
                                      ? _captureFace
                                      : _retakeFace),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                ),
                                backgroundColor: Colors.white.withOpacity(0.1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                _capturedImageBase64 == null
                                    ? 'SCAN'
                                    : 'RETAKE',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed:
                                  (isLoading ||
                                      !isLocationValid ||
                                      _capturedImageBase64 == null)
                                  ? null
                                  : () => markAttendance(
                                      context,
                                      employee['employee_id'],
                                    ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                ),
                                backgroundColor: const Color(0xFF2DD4BF),
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.black,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.fingerprint,
                                      size: 22,
                                      color: Colors.black,
                                    ),
                              label: const Text(
                                'SYNC ATTENDANCE',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }
}
