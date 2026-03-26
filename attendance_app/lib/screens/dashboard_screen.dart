import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import '../utils/browser_guard.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? salaryData;
  bool isLoadingSalary = true;
  List<Map<String, dynamic>> notifications = [];
  bool isLoadingNotifications = false;
  String notificationsError = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchSalaryData();
    });
  }

  Future<void> _fetchSalaryData() async {
    final employee =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    try {
      final response = await http.get(
        Uri.parse(
          'http://127.0.0.1:5000/employees/salary/${employee['employee_id']}',
        ),
      );
      if (response.statusCode == 200) {
        setState(() {
          salaryData = json.decode(response.body);
          isLoadingSalary = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoadingSalary = false);
    }
  }

  Future<void> _logout(
    BuildContext context,
    Map<String, dynamic> employee,
  ) async {
    try {
      await http.post(
        Uri.parse('http://127.0.0.1:5000/attendance/logout'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'employee_id': employee['employee_id']}),
      );
    } catch (_) {}
    Navigator.pushReplacementNamed(context, '/');
  }

  Future<void> _showNotifications(Map<String, dynamic> employee) async {
    setState(() {
      isLoadingNotifications = true;
      notificationsError = '';
    });

    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:5000/employees/notifications/${employee['employee_id']}'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        setState(() {
          notifications = data.map((e) => e as Map<String, dynamic>).toList();
        });
      } else {
        setState(() => notificationsError = 'Failed to load notifications');
      }
    } catch (_) {
      setState(() => notificationsError = 'Connection error');
    }

    setState(() => isLoadingNotifications = false);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF18181B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Notifications',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: isLoadingNotifications
            ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
            : notificationsError.isNotEmpty
            ? Text(notificationsError, style: const TextStyle(color: Colors.redAccent))
            : notifications.isEmpty
            ? Center(
                child: Text('No notifications', style: TextStyle(color: Colors.blueGrey.shade300)),
              )
            : SizedBox(
                width: 350,
                height: 400,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: notifications.length,
                  itemBuilder: (context, idx) {
                    final n = notifications[idx];
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.notifications_active, color: Colors.cyanAccent),
                        title: Text(
                          n['message'] ?? '',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        subtitle: Text(
                          'Date: ${n['date']}',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                        ),
                      ),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _showLeaveDialog(BuildContext context, Map<String, dynamic> employee) {
    String type = 'Full Day';
    final daysController = TextEditingController(text: '1');
    final hoursController = TextEditingController(text: '1');
    DateTime? startDate;
    DateTime? endDate;
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF18181B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Apply Leave',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: StatefulBuilder(
          builder: (context, setStateBuilder) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: type,
                      dropdownColor: const Color(0xFF27272A),
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white),
                      items: ['Full Day', 'Half Day', 'Hours']
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (v) => setStateBuilder(() => type = v!),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (type != 'Hours')
                  TextField(
                    controller: daysController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Days',
                      labelStyle: TextStyle(color: Colors.grey.shade400),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                if (type == 'Hours')
                  TextField(
                    controller: hoursController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Hours',
                      labelStyle: TextStyle(color: Colors.grey.shade400),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      builder: (context, child) =>
                          Theme(data: ThemeData.dark(), child: child!),
                    );
                    if (picked != null) {
                      setStateBuilder(() {
                        startDate = picked.start;
                        endDate = picked.end;
                      });
                    }
                  },
                  icon: const Icon(Icons.calendar_month, color: Colors.white),
                  label: const Text(
                    'Select Date Range',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F3F46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                if (startDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      endDate != null && endDate != startDate
                          ? '${startDate!.toLocal().toString().split(" ")[0]} to ${endDate!.toLocal().toString().split(" ")[0]}'
                          : startDate!.toLocal().toString().split(" ")[0],
                      style: const TextStyle(color: Colors.cyanAccent),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Reason',
                    labelStyle: TextStyle(color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              Navigator.pop(context);
              final body = {
                'employee_id': employee['employee_id'],
                'type': type,
                'reason': reasonController.text,
                'start_date': startDate?.toIso8601String().split('T').first,
                'end_date': endDate?.toIso8601String().split('T').first,
              };
              if (type == 'Hours')
                body['hours'] = double.tryParse(hoursController.text) ?? 0;
              else
                body['days'] = double.tryParse(daysController.text) ?? 0;
              await http.post(
                Uri.parse('http://127.0.0.1:5000/employees/leave/apply'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode(body),
              );
            },
            child: const Text(
              'Submit',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final employee =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    attachBeforeUnloadWarning('Please logout before closing this tab.');

    return WillPopScope(
      onWillPop: () async {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please securely sign out to exit.')),
        );
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF09090B),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: const Color(0xFF09090B).withOpacity(0.7)),
            ),
          ),
          title: const Text(
            'Employee Workspace',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 24,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(Icons.notifications_active_rounded, color: Colors.cyanAccent),
                onPressed: () => _showNotifications(employee),
                tooltip: 'Notifications',
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                onPressed: () => _logout(context, employee),
                tooltip: 'Secure Logout',
              ),
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 80,
            left: 24,
            right: 24,
            bottom: 40,
          ),
          children: [
            // Welcome Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.white24,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: TextStyle(
                            color: Colors.blue.shade100,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${employee['name']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${employee['department']} • ID: ${employee['employee_id']}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Quick Actions
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Mark\nAttendance',
                    color: Colors.cyanAccent,
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/mark_attendance',
                      arguments: employee,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.history_rounded,
                    title: 'View\nHistory',
                    color: Colors.purpleAccent,
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/attendance_history',
                      arguments: employee,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.event_note_rounded,
                    title: 'Apply\nLeave',
                    color: Colors.orangeAccent,
                    onTap: () => _showLeaveDialog(context, employee),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Salary Card
            const Text(
              'Payroll Overview',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: isLoadingSalary
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                          color: Colors.cyanAccent,
                        ),
                      ),
                    )
                  : salaryData != null
                  ? Column(
                      children: [
                        _InfoRow(
                          label: 'Base Monthly Salary',
                          value: '₹${salaryData!['monthly_salary']}',
                          isHighlight: true,
                        ),
                        const Divider(color: Colors.white10, height: 30),
                        _InfoRow(
                          label: 'Paid Leaves Available',
                          value: '${salaryData!['paid_leave_allowed']} d',
                        ),
                        _InfoRow(
                          label: 'Leaves Taken',
                          value: '${salaryData!['total_leaves']} d',
                          valueColor: Colors.orangeAccent,
                        ),
                        _InfoRow(
                          label: 'Late Minutes Total',
                          value: '${salaryData!['late_minutes']} min',
                          valueColor: Colors.redAccent,
                        ),
                        const Divider(color: Colors.white10, height: 30),
                        _InfoRow(
                          label: 'Total Deductions',
                          value:
                              '- ₹${salaryData!['total_deduction'].toStringAsFixed(2)}',
                          valueColor: Colors.redAccent,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.greenAccent.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Final Payout',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '₹${salaryData!['final_salary'].toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      'Payroll data unavailable',
                      style: TextStyle(color: Colors.grey),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isHighlight;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: isHighlight ? 16 : 14,
              fontWeight: isHighlight ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: isHighlight ? 18 : 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
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
          color: _isHovering ? const Color(0xFF222226) : const Color(0xFF18181B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isHovering
                ? widget.color.withOpacity(0.6)
                : widget.color.withOpacity(0.2),
            width: _isHovering ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovering
                  ? widget.color.withOpacity(0.3)
                  : widget.color.withOpacity(0.05),
              blurRadius: _isHovering ? 16 : 10,
              offset: Offset(0, _isHovering ? 8 : 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.color.withOpacity(_isHovering ? 0.25 : 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon, size: 28, color: widget.color),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
