import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../attendance/attendance_dashboard_section.dart';
import '../shared/employee_ui.dart';
import '../../services/api_config.dart';
import '../../services/auth_service.dart';
import '../../services/auth_storage.dart';
import '../../services/hrms_payslip_api.dart';

class EmployeeDashboardPage extends StatefulWidget {
  const EmployeeDashboardPage({super.key});
  @override
  State<EmployeeDashboardPage> createState() => _EmployeeDashboardPageState();
}

class _EmployeeDashboardPageState extends State<EmployeeDashboardPage> {
  bool menuOpen = false;
  static const routes = <String>{
    '/employee/dashboard',
    '/employee/attendance',
    '/employee/clock-log',
    '/employee/leave',
    '/employee/permission',
    '/employee/extra-hours',
    '/employee/salary',
    '/employee/tracking',
  };
  void go(String route) {
    setState(() => menuOpen = false);
    if (routes.contains(route)) {
      Navigator.pushNamed(context, route);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This page is not available yet.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
        bottomNavigationBar: mobile ? const EmployeeMobileBottomNav(route: '/employee/dashboard') : null,
        body: SafeArea(
            child: Stack(children: [
      Column(children: [
        _Header(
            mobile: mobile,
            open: menuOpen,
            onMenu: () => setState(() => menuOpen = !menuOpen)),
        Expanded(
            child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              mobile ? 18 : 36, mobile ? 24 : 34, mobile ? 18 : 36, mobile ? 110 : 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: const _Content(),
          ),
        )),
      ]),
      if (menuOpen)
        _Menu(onClose: () => setState(() => menuOpen = false), onSelect: go),
    ])));
  }
}

class _Header extends StatefulWidget {
  const _Header(
      {required this.mobile, required this.open, required this.onMenu});
  final bool mobile, open;
  final VoidCallback onMenu;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  String _fullName = 'Employee';
  String _staffId = '';
  String _initials = 'E';

  @override
  void initState() {
    super.initState();
    _loadStoredIdentity();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfile();
      _loadEmployee();
    });
  }

  void _setIdentity(String? name, String? staffId) {
    final resolved = (name ?? '').trim();
    if (resolved.isEmpty) return;
    final words = resolved.split(RegExp(r'\s+'));
    setState(() {
      _fullName = resolved;
      _staffId = (staffId ?? '').trim();
      _initials = words.take(2).where((word) => word.isNotEmpty).map((word) => word[0].toUpperCase()).join();
      if (_initials.isEmpty) _initials = 'E';
    });
  }

  Future<void> _loadStoredIdentity() async {
    try {
      final raw = await AuthStorage.getString('user_data');
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw);
      if (data is Map && mounted) {
        _setIdentity(
        data['fullName']?.toString() ?? data['full_name']?.toString() ?? data['name']?.toString(),
        data['staffId']?.toString() ?? data['staff_id']?.toString() ?? data['employee_id']?.toString(),
      );
      }
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    final token = context.read<AuthService>().token ?? await AuthStorage.getString('auth_token');
    if (token == null || token.isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/auth/me'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      final body = jsonDecode(response.body);
      if (response.statusCode != 200 || body is! Map || body['success'] != true || body['data'] is! Map || !mounted) return;
      final profile = Map<String, dynamic>.from(body['data'] as Map);
      _setIdentity(profile['fullName']?.toString() ?? profile['full_name']?.toString(), profile['staffId']?.toString() ?? profile['staff_id']?.toString());
    } catch (_) {}
  }

  Future<void> _loadEmployee() async {
    final auth = context.read<AuthService>();
    final token = auth.token ?? await AuthStorage.getString('auth_token');
    if (token == null || token.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/attendance/header-status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return;
      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true || body['data'] is! Map) {
        return;
      }

      final data = Map<String, dynamic>.from(body['data'] as Map);
      final name = (data['full_name']?.toString() ?? '').trim();
      final staffId = (data['staff_id']?.toString() ?? '').trim();
      if (!mounted || name.isEmpty) return;

      _setIdentity(name, staffId);
    } catch (_) {
      // Keep the neutral placeholder if the profile endpoint is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        height: widget.mobile ? 78 : 88,
        padding: EdgeInsets.symmetric(horizontal: widget.mobile ? 18 : 36),
        decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE7EDF7))),
            boxShadow: [
              BoxShadow(
                  color: Color(0x0D102C5A),
                  blurRadius: 14,
                  offset: Offset(0, 4))
            ]),
        child: Row(children: [
          Image.asset('assets/images/godigital_logo.png',
              height: widget.mobile ? 45 : 53,
              width: widget.mobile ? 136 : 164,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft),
          if (!widget.mobile) ...[
            const SizedBox(width: 24),
            const Expanded(child: Center(child: _DashboardTopNav())),
          ] else
            const Spacer(),
          if (!widget.mobile) ...[
            const Text('Employee Portal',
                style: TextStyle(color: employeeMuted)),
            const SizedBox(width: 24)
          ],
          const EmployeeNotificationButton(),
          const SizedBox(width: 18),
          EmployeeProfileMenu(
            radius: 25,
            initials: _initials,
            fullName: _fullName,
            staffId: _staffId,
          ),
        ]),
      );
}

class _DashboardTopNav extends StatelessWidget {
  const _DashboardTopNav();

  static const _items = <(String, String)>[
    ('Dashboard', '/employee/dashboard'),
    ('Attendance', '/employee/attendance'),
    ('Clock In / Out', '/employee/clock-log'),
    ('Leave', '/employee/leave'),
    ('Permission', '/employee/permission'),
    ('Extra Hours', '/employee/extra-hours'),
    ('Salary', '/employee/salary'),
    ('Tracking', '/employee/tracking'),
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7FB),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: const Color(0xFFE7ECF4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _items.map((item) {
              final active = item.$2 == '/employee/dashboard';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: active ? employeeBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(26),
                    onTap: active ? null : () => Navigator.pushNamed(context, item.$2),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(item.$1, style: TextStyle(color: active ? Colors.white : employeeMuted, fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );
}

class _Content extends StatelessWidget {
  const _Content();
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const AttendanceDashboardSection(),
        const SizedBox(height: 18),
        const _Actions(
            'ATTENDANCE', employeeBlue, Icons.calendar_month_outlined, [
          ('Calendar', Icons.calendar_today_outlined, '/employee/attendance'),
          ('Clock Log', Icons.history_rounded, '/employee/clock-log')
        ]),
        const SizedBox(height: 12),
        const _Actions('LEAVE', Color(0xFF6C36E8), Icons.eco_outlined, [
          ('Apply Leave', Icons.note_add_outlined, '/employee/leave'),
          ('My Requests', Icons.assignment_outlined, '/employee/leave')
        ]),
        const SizedBox(height: 12),
        const _Actions(
            'PERMISSION', Color(0xFF5B35D5), Icons.verified_user_outlined, [
          (
            'Apply Permission',
            Icons.verified_user_outlined,
            '/employee/permission'
          ),
          ('View Log', Icons.history_rounded, '/employee/permission')
        ]),
        const SizedBox(height: 12),
        const _Actions('EXTRA HOURS', employeeOrange, Icons.more_time_rounded, [
          ('Log Hours', Icons.more_time_rounded, '/employee/extra-hours'),
          ('0h', Icons.timelapse_rounded, null)
        ]),
        const SizedBox(height: 12),
        const _DynamicSalaryAction(),
        const SizedBox(height: 12),
        const _Actions(
            'TRACKING', Color(0xFF079B9B), Icons.location_on_outlined, [
          ('Live Tracking', Icons.location_on_outlined, '/employee/tracking'),
          ('Route History', Icons.map_outlined, '/employee/tracking')
        ]),
      ]);
}

class _DynamicSalaryAction extends StatefulWidget {
  const _DynamicSalaryAction();
  @override State<_DynamicSalaryAction> createState() => _DynamicSalaryActionState();
}

class _DynamicSalaryActionState extends State<_DynamicSalaryAction> {
  late final Future<Map<String, dynamic>> _summary = HrmsPayslipApi.summary();

  String _money(dynamic value) {
    final amount = value is num ? value : num.tryParse('$value');
    if (amount == null) return 'Not Set';
    return '₹${amount.round().toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+$)'), (_) => ',')}';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _summary,
        builder: (_, snapshot) {
          final payroll = snapshot.data?['payroll'];
          final map = payroll is Map ? payroll : const <String, dynamic>{};
          final netPay = map['net_pay'] ?? map['updated_salary'] ?? map['monthly_salary'];
          return _Actions('SALARY', const Color(0xFF07368D), Icons.currency_rupee_rounded, [
            ('Net Pay ${_money(netPay)}', Icons.currency_rupee_rounded, null),
            ('View Payslip', Icons.description_outlined, '/employee/salary'),
          ]);
        },
      );
}

class _Actions extends StatelessWidget {
  const _Actions(this.title, this.color, this.icon, this.actions);
  final String title;
  final Color color;
  final IconData icon;
  final List<(String, IconData, String?)> actions;
  @override
  Widget build(BuildContext context) => EmployeeCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
                color: color,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14))),
            child: Row(children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 14),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800))
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _ActionTile(action: actions[i], color: color)),
              ],
            ]),
          ),
        ]),
      );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.color});
  final (String, IconData, String?) action;
  final Color color;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: action.$3 == null
            ? null
            : () => Navigator.pushNamed(context, action.$3!,
                arguments: switch (action.$1) {
                  'Route History' => 'history',
                  'View Log' => 'log',
                  'My Requests' => 'requests',
                  _ => null
                }),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 15),
          decoration: BoxDecoration(
              border: Border.all(color: employeeLine),
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Icon(action.$2, color: color),
            const SizedBox(width: 10),
            Expanded(
                child: Text(action.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: employeeNavy, fontWeight: FontWeight.w600))),
            if (action.$3 != null)
              const Icon(Icons.chevron_right_rounded, color: employeeNavy),
          ]),
        ),
      );
}

class _Menu extends StatelessWidget {
  const _Menu({required this.onClose, required this.onSelect});
  final VoidCallback onClose;
  final ValueChanged<String> onSelect;
  static const items = [
    ('Dashboard', Icons.grid_view_rounded, '/employee/dashboard'),
    ('Attendance', Icons.calendar_month_outlined, '/employee/attendance'),
    ('Clock In / Out', Icons.schedule_rounded, '/employee/clock-log'),
    ('Leave', Icons.description_outlined, '/employee/leave'),
    ('Permission', Icons.verified_user_outlined, '/employee/permission'),
    ('Extra Hours', Icons.more_time_rounded, '/employee/extra-hours'),
    ('Salary', Icons.currency_rupee_rounded, '/employee/salary'),
    ('Tracking', Icons.location_on_outlined, '/employee/tracking')
  ];
  @override
  Widget build(BuildContext context) => Stack(children: [
        GestureDetector(
            onTap: onClose, child: Container(color: const Color(0x4A07143F))),
        Align(
            alignment: Alignment.centerRight,
            child: Material(
                color: Colors.white,
                elevation: 24,
                child: SafeArea(
                    child: SizedBox(
                        width: MediaQuery.sizeOf(context)
                            .width
                            .clamp(280.0, 350.0),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(22, 19, 12, 15),
                                  child: Row(children: [
                                    const Expanded(
                                        child: Text('Menu',
                                            style: TextStyle(
                                                color: employeeNavy,
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800))),
                                    IconButton(
                                        onPressed: onClose,
                                        icon: const Icon(Icons.close_rounded,
                                            color: employeeNavy))
                                  ])),
                              const Divider(height: 1, color: employeeLine),
                              const SizedBox(height: 8),
                              ...items.map((item) => InkWell(
                                  onTap: () => onSelect(item.$3),
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 23, vertical: 15),
                                      child: Row(children: [
                                        Icon(item.$2,
                                            color: employeeBlue, size: 22),
                                        const SizedBox(width: 16),
                                        Text(item.$1,
                                            style: const TextStyle(
                                                color: employeeNavy,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600))
                                      ]))))
                            ])))))
      ]);
}
