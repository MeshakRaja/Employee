import re

def update_file():
    filepath = r"c:\Student Management System\attendance_app\lib\screens\admin_page.dart"
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # 1. Add dart:ui import
    if "import 'dart:ui';" not in content:
        content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'dart:ui';")

    # 2. Update _buildDrawer
    drawer_old = """  Drawer _buildDrawer(BuildContext context) {
    Widget item(IconData icon, String title, VoidCallback onTap) {
      return ListTile(
        leading: Icon(icon, color: Colors.white),
        title: Text(title, style: TextStyle(color: Colors.white)),
        onTap: onTap,
      );
    }

    return Drawer(
      backgroundColor: Color(0xFF0e1526),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.teal,
                    child: Icon(
                      Icons.admin_panel_settings,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Admin",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        "Dashboard",
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(color: Colors.white24),
            item(Icons.dashboard, "Dashboard", () => Navigator.pop(context)),
            item(Icons.people, "Employees", () => Navigator.pop(context)),
            item(
              Icons.event_available,
              "Attendance",
              () => Navigator.pop(context),
            ),
            item(
              Icons.request_quote,
              "Leave Requests",
              () => Navigator.pop(context),
            ),
            item(Icons.payments, "Salary", () => Navigator.pop(context)),
            Spacer(),
            Divider(color: Colors.white24),
            item(
              Icons.logout,
              "Logout",
              () => Navigator.pushReplacementNamed(context, '/'),
            ),
          ],
        ),
      ),
    );
  }"""
    
    drawer_new = """  Drawer _buildDrawer(BuildContext context) {
    Widget item(IconData icon, String title, VoidCallback onTap) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        leading: Icon(icon, color: Colors.white70, size: 22),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
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
                      gradient: const LinearGradient(colors: [Color(0xFF2DD4BF), Color(0xFF0D9488)]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF0D9488).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Administrator",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 4),
                      Text("Workspace Center", style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Divider(color: Colors.white.withOpacity(0.1), thickness: 1),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  item(Icons.dashboard_rounded, "Dashboard", () => Navigator.pop(context)),
                  const SizedBox(height: 4),
                  item(Icons.people_alt_rounded, "Employees", () => Navigator.pop(context)),
                  const SizedBox(height: 4),
                  item(Icons.fact_check_rounded, "Attendance", () => Navigator.pop(context)),
                  const SizedBox(height: 4),
                  item(Icons.event_note_rounded, "Leave Requests", () => Navigator.pop(context)),
                  const SizedBox(height: 4),
                  item(Icons.payments_rounded, "Salary & Payroll", () => Navigator.pop(context)),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Divider(color: Colors.white.withOpacity(0.1), thickness: 1),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: item(Icons.logout_rounded, "Secure Logout", () => Navigator.pushReplacementNamed(context, '/')),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }"""
    content = content.replace(drawer_old, drawer_new)

    # 3. Update build method
    
    # We will use regex to replace everything from @override Widget build(BuildContext context) to the end of the method
    # It ends before @override void dispose()
    
    build_regex = re.compile(r'  @override\n  Widget build\(BuildContext context\) \{.*?(?=  @override\n  void dispose\(\) \{)', re.DOTALL)
    
    build_new = """  @override
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
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: const Color(0xFF0B1120).withOpacity(0.8)),
          ),
        ),
        title: const Text(
          'Command Center',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 24, letterSpacing: -0.5),
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
                gradient: const LinearGradient(colors: [Color(0xFF2DD4BF), Color(0xFF0D9488)]),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF0D9488).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
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
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => showEmployeeDialog(),
                    icon: const Icon(Icons.person_add_rounded, size: 20),
                    label: const Text("Add Member", style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  child: isLoading
                      ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                      : employees.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'No team members registered yet',
                              style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 15),
                            ),
                          ),
                        )
                      : Column(
                          children: employees.map((employee) {
                            return _EmployeeTile(
                              name: employee['name'],
                              id: employee['employee_id'],
                              department: employee['department'],
                              salary: "₹${(employee['monthly_salary'] ?? '12000')}",
                              onEdit: () => showEmployeeDialog(employee: employee),
                              onDelete: () => deleteEmployee(employee['id']),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 24),
                _SectionCard(
                  title: "Today's Attendance",
                  child: attendanceLoading
                      ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                      : attendanceError.isNotEmpty
                      ? Center(child: Text(attendanceError, style: const TextStyle(color: Colors.redAccent)))
                      : attendanceToday.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'No check-ins recorded today',
                              style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 15),
                            ),
                          ),
                        )
                      : Column(
                          children: attendanceToday.map((a) {
                            final lateLabel = a['late_label'] ?? '${a['late_minutes']}m';
                            final lateColor = (a['late_minutes'] ?? 0) > 0
                                ? const Color(0xFFF43F5E)
                                : const Color(0xFF10B981);
                            return _InfoTile(
                              title: a['name'],
                              subtitle: 'ID: ${a['employee_id']} • ${a['department']}\\nIn: ${a['login_time'] ?? '-'}  Out: ${a['logout_time'] ?? '-'}',
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
                      ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                      : leaveError.isNotEmpty
                      ? Center(child: Text(leaveError, style: const TextStyle(color: Colors.redAccent)))
                      : leaveRequests.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'No pending leave requests',
                              style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 15),
                            ),
                          ),
                        )
                      : Column(
                          children: leaveRequests.map((lr) {
                            final isPending = (lr['status'] ?? '') == 'Pending';
                            final dateLabel = (lr['end_date'] ?? lr['start_date']) != lr['start_date']
                                ? '${lr['start_date']} - ${lr['end_date']}'
                                : '${lr['start_date'] ?? '-'}';
                            final duration = lr['hours'] != null ? '${lr['hours']} hrs' : '${lr['days']} d';
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${lr['employee_name']}',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                                      ),
                                    ),
                                    if (!isPending)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: lr['status'] == 'Approve' ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: lr['status'] == 'Approve' ? Colors.green.withOpacity(0.5) : Colors.orange.withOpacity(0.5)),
                                        ),
                                        child: Text(
                                          lr['status'],
                                          style: TextStyle(color: lr['status'] == 'Approve' ? Colors.greenAccent : Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    'ID: ${lr['employee_id']} • ${lr['department']}\\n'
                                    'Type: ${lr['type']}  • $duration\\n'
                                    'Date: $dateLabel\\n'
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
                                            onTap: () => _updateLeave(lr['id'], 'Approve'),
                                          ),
                                          _ActionChip(
                                            icon: Icons.close_rounded,
                                            color: const Color(0xFFF43F5E),
                                            onTap: () => _updateLeave(lr['id'], 'Reject'),
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
                      ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                      : salaryError.isNotEmpty
                      ? Center(child: Text(salaryError, style: const TextStyle(color: Colors.redAccent)))
                      : salaryData.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'No salary data available',
                              style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 15),
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
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                title: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${s['name']}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                                    ),
                                    Text(
                                      '₹${s['final_salary'].toStringAsFixed(2)}',
                                      style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    'ID: ${s['employee_id']} • Dept: ${s['department']}\\n'
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
  }\n"""
    
    content = build_regex.sub(build_new, content)

    # 4. Replace UI classes at the bottom
    classes_regex = re.compile(r'class _SectionCard extends StatelessWidget \{.*', re.DOTALL)
    
    classes_new = """class _SectionCard extends StatelessWidget {
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
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Text(
            'ID: $id • $department\\nSalary: $salary',
            style: TextStyle(color: Colors.blueGrey.shade300, height: 1.4, fontSize: 13),
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

class _SummaryCard extends StatelessWidget {
  final SummaryItem item;
  const _SummaryCard({required this.item});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            item.color.withOpacity(0.2),
            item.color.withOpacity(0.02)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: item.color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, color: item.color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.value,
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
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Text(
            subtitle,
            style: TextStyle(color: Colors.blueGrey.shade300, height: 1.4, fontSize: 13),
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
            style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 12),
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
"""
    
    content = classes_regex.sub(classes_new, content)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
        
    print("UI replaced successfully")

if __name__ == '__main__':
    update_file()
