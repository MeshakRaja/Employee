import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'add_employee_page.dart';

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

  @override
  void initState() {
    super.initState();
    _refreshAllData();
  }

  Future<void> _refreshAllData() async {
    await Future.wait([
      fetchEmployees(),
      fetchNotifications(),
      fetchTodayAttendance(),
      fetchLeaveRequests(),
      fetchSalaryData(),
    ]);
  }

  // Data calls
  Future<void> fetchEmployees() async {
    try {
      final response = await http.get(
        Uri.parse('${AdminPage.baseUrl}/admin/employees'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        if (mounted) {
          setState(() {
            employees = data.map((e) => e as Map<String, dynamic>).toList();
            isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => isLoading = false);
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

  Future<void> deleteEmployee(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('${AdminPage.baseUrl}/admin/employees/$id'),
      );
      final data = json.decode(response.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Employee deleted')),
        );
        fetchEmployees();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection error')),
        );
      }
    }
  }

  Future<void> fetchNotifications() async {
    if (mounted) setState(() => notificationsLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${AdminPage.baseUrl}/admin/notifications'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        if (mounted) {
          setState(() => notifications = data.map((e) => e as Map<String, dynamic>).toList());
        }
      }
    } catch (_) {}
    if (mounted) setState(() => notificationsLoading = false);
  }

  Future<void> fetchTodayAttendance() async {
    if (mounted) setState(() => attendanceLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${AdminPage.baseUrl}/admin/attendance/today'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        if (mounted) {
          setState(() => attendanceToday = data.map((e) => e as Map<String, dynamic>).toList());
        }
      }
    } catch (_) {}
    if (mounted) setState(() => attendanceLoading = false);
  }

  Future<void> fetchLeaveRequests() async {
    if (mounted) setState(() => leaveLoading = true);
    try {
      final res = await http.get(
        Uri.parse('${AdminPage.baseUrl}/admin/leaves'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as List;
        if (mounted) {
          setState(() => leaveRequests = data.map((e) => e as Map<String, dynamic>).toList());
        }
      }
    } catch (_) {}
    if (mounted) setState(() => leaveLoading = false);
  }

  Future<void> fetchSalaryData() async {
    if (mounted) setState(() => salaryLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${AdminPage.baseUrl}/admin/salary/all'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        if (mounted) {
          setState(() => salaryData = data.map((e) => e as Map<String, dynamic>).toList());
        }
      }
    } catch (_) {}
    if (mounted) setState(() => salaryLoading = false);
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

  void _navigateToAddEmployee({Map<String, dynamic>? employee}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEmployeePage(employee: employee),
      ),
    );

    if (result == true) {
      fetchEmployees(); // Refresh list if an employee was added/updated
    }
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
                  item(Icons.dashboard_rounded, "Dashboard", () => Navigator.pop(context)),
                  item(Icons.people_alt_rounded, "Employees", () => Navigator.pop(context)),
                  item(Icons.fact_check_rounded, "Attendance", () => Navigator.pop(context)),
                  item(Icons.event_note_rounded, "Leave Requests", () => Navigator.pop(context)),
                  item(Icons.payments_rounded, "Salary & Payroll", () => Navigator.pop(context)),
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

  @override
  Widget build(BuildContext context) {
    final presentCount = attendanceToday.length;
    final totalEmployees = employees.length;
    final pendingLeaves = leaveRequests.where((lr) => (lr['status'] ?? '') == 'Pending').length;
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
          child: RefreshIndicator(
            onRefresh: _refreshAllData,
            color: const Color(0xFF2DD4BF),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Overview",
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _SummaryGrid(
                    items: [
                      SummaryItem(title: "Total Staff", value: "$totalEmployees", icon: Icons.groups_rounded, color: const Color(0xFF3B82F6)),
                      SummaryItem(title: "Present Today", value: "$presentCount", icon: Icons.how_to_reg_rounded, color: const Color(0xFF10B981)),
                      SummaryItem(title: "Absent Today", value: "$absent", icon: Icons.person_off_rounded, color: const Color(0xFFF43F5E)),
                      SummaryItem(title: "Pending Leaves", value: "$pendingLeaves", icon: Icons.pending_actions_rounded, color: const Color(0xFFF59E0B)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _navigateToAddEmployee(),
                      icon: const Icon(Icons.person_add_rounded, size: 20),
                      label: const Text("Add Member", style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    child: isLoading
                        ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                        : employees.isEmpty
                            ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('No team members registered yet', style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 15))))
                            : Column(
                                children: employees.map((employee) {
                                  return _EmployeeTile(
                                    name: employee['name'],
                                    id: employee['employee_id'],
                                    department: employee['department'],
                                    salary: "₹${(employee['monthly_salary'] ?? '12000')}",
                                    onEdit: () => _navigateToAddEmployee(employee: employee),
                                    onDelete: () => deleteEmployee(employee['id']),
                                  );
                                }).toList(),
                              ),
                  ),
                  const SizedBox(height: 24),
                  _SectionCard(
                    title: "Today's Attendance",
                    child: Column(
                      children: attendanceToday.isEmpty
                          ? [Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('No check-ins recorded today', style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 15))))]
                          : attendanceToday.map((a) {
                              final lateColor = (a['late_minutes'] ?? 0) > 0 ? const Color(0xFFF43F5E) : const Color(0xFF10B981);
                              return _InfoTile(
                                title: a['name'],
                                subtitle: 'ID: ${a['employee_id']} • ${a['department']}\nIn: ${a['login_time'] ?? '-'}  Out: ${a['logout_time'] ?? '-'}',
                                badge: a['late_label'] ?? '${a['late_minutes']}m',
                                badgeColor: lateColor,
                              );
                            }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SectionCard(
                    title: 'Leave Requests',
                    child: Column(
                      children: leaveRequests.isEmpty
                          ? [Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('No pending leave requests', style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 15))))]
                          : leaveRequests.map((lr) {
                              final isPending = (lr['status'] ?? '') == 'Pending';
                              final dateLabel = (lr['end_date'] ?? lr['start_date']) != lr['start_date'] ? '${lr['start_date']} - ${lr['end_date']}' : '${lr['start_date'] ?? '-'}';
                              final duration = lr['hours'] != null ? '${lr['hours']} hrs' : '${lr['days']} d';
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  title: Row(children: [
                                    Expanded(child: Text('${lr['employee_name']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16))),
                                    if (!isPending)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(color: lr['status'] == 'Approved' ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: lr['status'] == 'Approved' ? Colors.green.withOpacity(0.5) : Colors.orange.withOpacity(0.5))),
                                        child: Text(lr['status'], style: TextStyle(color: lr['status'] == 'Approved' ? Colors.greenAccent : Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                      ),
                                  ]),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text('ID: ${lr['employee_id']} • ${lr['department']}\nType: ${lr['type']}  • $duration\nDate: $dateLabel\nReason: ${lr['reason'] ?? ''}', style: TextStyle(color: Colors.blueGrey.shade200, height: 1.5, fontSize: 14)),
                                  ),
                                  trailing: isPending
                                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                                          _ActionChip(icon: Icons.check_rounded, color: const Color(0xFF10B981), onTap: () => _updateLeave(lr['id'], 'Approve')),
                                          _ActionChip(icon: Icons.close_rounded, color: const Color(0xFFF43F5E), onTap: () => _updateLeave(lr['id'], 'Reject')),
                                        ])
                                      : null,
                                ),
                              );
                            }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SectionCard(
                    title: 'Salary Monitoring',
                    child: Column(
                      children: salaryData.isEmpty
                          ? [Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('No salary data available', style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 15))))]
                          : salaryData.map((s) {
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                    Text('${s['name']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                                    Text('₹${s['final_salary'].toStringAsFixed(2)}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                                  ]),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text('ID: ${s['employee_id']} • Dept: ${s['department']}\nBase: ₹${s['monthly_salary']} • Late: ${s['late_minutes']}m • Leaves: ${s['total_leaves']}', style: TextStyle(color: Colors.blueGrey.shade300, height: 1.4, fontSize: 13)),
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
      ),
    );
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
      decoration: BoxDecoration(color: const Color(0xFF1E293B).withOpacity(0.5), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.08)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5))), if (action != null) action!]),
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
  const _EmployeeTile({required this.name, required this.id, required this.department, required this.salary, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF3B82F6).withOpacity(0.15), shape: BoxShape.circle), child: const Icon(Icons.person, color: Color(0xFF60A5FA))),
        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 6.0), child: Text('ID: $id • $department\nSalary: $salary', style: TextStyle(color: Colors.blueGrey.shade300, height: 1.4, fontSize: 13))),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.edit_outlined, color: Color(0xFF2DD4BF)), onPressed: onEdit, tooltip: 'Edit'),
          IconButton(icon: const Icon(Icons.delete_outline, color: Color(0xFFF43F5E)), onPressed: onDelete, tooltip: 'Delete'),
        ]),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final List<SummaryItem> items;
  const _SummaryGrid({required this.items});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 650;
      final crossAxis = isWide ? 4 : 2;
      return GridView.count(physics: const NeverScrollableScrollPhysics(), crossAxisCount: crossAxis, shrinkWrap: true, childAspectRatio: isWide ? 1.8 : 1.6, crossAxisSpacing: 16, mainAxisSpacing: 16, children: items.map((i) => _SummaryCard(item: i)).toList());
    });
  }
}

class SummaryItem {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  SummaryItem({required this.title, required this.value, required this.icon, required this.color});
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
        decoration: BoxDecoration(gradient: LinearGradient(colors: _isHovering ? [widget.item.color.withOpacity(0.35), widget.item.color.withOpacity(0.08)] : [widget.item.color.withOpacity(0.2), widget.item.color.withOpacity(0.02)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(20), border: Border.all(color: _isHovering ? widget.item.color.withOpacity(0.6) : widget.item.color.withOpacity(0.2), width: _isHovering ? 1.5 : 1.0), boxShadow: [BoxShadow(color: _isHovering ? widget.item.color.withOpacity(0.3) : Colors.black.withOpacity(0.1), blurRadius: _isHovering ? 16 : 10, offset: Offset(0, _isHovering ? 8 : 4))]),
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          AnimatedContainer(duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: widget.item.color.withOpacity(_isHovering ? 0.25 : 0.15), borderRadius: BorderRadius.circular(14)), child: Icon(widget.item.icon, color: widget.item.color, size: 28)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(widget.item.title, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13, fontWeight: FontWeight.w500)), const SizedBox(height: 6), Text(widget.item.value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))])),
        ]),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  const _InfoTile({required this.title, required this.subtitle, required this.badge, required this.badgeColor});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 6.0), child: Text(subtitle, style: TextStyle(color: Colors.blueGrey.shade300, height: 1.4, fontSize: 13))),
        trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: badgeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: badgeColor.withOpacity(0.3))), child: Text(badge, style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 12))),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(margin: const EdgeInsets.symmetric(horizontal: 4), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.3))), child: Icon(icon, color: color, size: 20)),
      ),
    );
  }
}
