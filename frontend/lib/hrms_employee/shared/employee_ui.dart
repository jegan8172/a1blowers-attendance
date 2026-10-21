import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/api_config.dart';
import '../../services/auth_service.dart';
import '../../services/auth_storage.dart';
import '../../screens/login_screen.dart';

const employeeBlue = Color(0xFF1769E0);
const employeeNavy = Color(0xFF07143F);
const employeeMuted = Color(0xFF66738F);
const employeeLine = Color(0xFFDCE4F0);
const employeePurple = Color(0xFF772AE4);
const employeeOrange = Color(0xFFFF7100);
const employeeGreen = Color(0xFF08A978);

class EmployeeScaffold extends StatelessWidget {
  const EmployeeScaffold({
    super.key,
    required this.route,
    required this.title,
    required this.subtitle,
    required this.desktop,
    required this.mobile,
    this.desktopHeaderAction,
  });

  final String route;
  final String title;
  final String subtitle;
  final Widget desktop;
  final Widget mobile;
  final Widget? desktopHeaderAction;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 600) {
      return Scaffold(
        bottomNavigationBar: EmployeeMobileBottomNav(route: route),
        body: SafeArea(
          child: Column(
            children: [
              EmployeeTopNavigation(route: route, mobile: true),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
                  child: mobile,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: Column(
        children: [
          EmployeeTopNavigation(route: route),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(30, 26, 30, 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: employeeNavy,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      ?desktopHeaderAction,
                    ],
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: employeeMuted,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ] else
                    const SizedBox(height: 12),
                  desktop,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmployeeMobileBottomNav extends StatelessWidget {
  const EmployeeMobileBottomNav({super.key, required this.route});
  final String route;

  static const _primaryItems = <_NavItem>[
    _NavItem('/employee/dashboard', 'Dashboard', Icons.grid_view_rounded),
    _NavItem(
      '/employee/attendance',
      'Attendance',
      Icons.calendar_month_outlined,
    ),
  ];

  static const _moreItems = <_NavItem>[
    _NavItem('/employee/clock-log', 'Clock In / Out', Icons.schedule_rounded),
    _NavItem('/employee/leave', 'Leave', Icons.description_outlined),
    _NavItem('/employee/permission', 'Permission', Icons.verified_user_outlined),
    _NavItem('/employee/extra-hours', 'Extra Hours', Icons.more_time_rounded),
    _NavItem('/employee/salary', 'Salary', Icons.currency_rupee_rounded),
    _NavItem('/employee/tracking', 'Tracking', Icons.location_on_rounded),
  ];

  bool get _moreActive => _moreItems.any((item) => item.route == route);

  Future<void> _showMore(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('More', style: TextStyle(
              color: employeeNavy, fontSize: 20, fontWeight: FontWeight.w800,
            )),
            const SizedBox(height: 12),
            ..._moreItems.map((item) => ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE8EB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: employeeBlue),
              ),
              title: Text(item.label, style: const TextStyle(
                color: employeeNavy, fontWeight: FontWeight.w700,
              )),
              trailing: const Icon(Icons.chevron_right_rounded, color: employeeMuted),
              onTap: () {
                Navigator.pop(sheetContext);
                if (item.route != route) {
                  Navigator.of(context).pushReplacementNamed(item.route);
                }
              },
            )),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(14, 4, 14, 12),
    child: Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF172554),
        borderRadius: BorderRadius.circular(34),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [..._primaryItems, ..._moreItems]
              .map((item) => _mobileItem(context, item))
              .toList(),
        ),
      ),
    ),
  );

  Widget _mobileItem(BuildContext context, _NavItem item) {
    final active = item.route == route;
    return SizedBox(
      width: 72,
      height: 62,
      child: Tooltip(
        message: item.label,
        child: InkWell(
          onTap: active
              ? null
              : () => Navigator.of(context).pushReplacementNamed(item.route),
          borderRadius: BorderRadius.circular(25),
          child: Center(
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: active ? employeeBlue : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(item.icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class EmployeeSidebar extends StatelessWidget {
  const EmployeeSidebar({super.key, required this.route});
  final String route;

  static const items = <_NavItem>[
    _NavItem('/employee/dashboard', 'Dashboard', Icons.grid_view_rounded),
    _NavItem(
      '/employee/attendance',
      'Attendance',
      Icons.calendar_month_outlined,
    ),
    _NavItem('/employee/clock-log', 'Clock In / Out', Icons.schedule_rounded),
    _NavItem(
      '/employee/leave',
      'Leave',
      Icons.description_outlined,
      badge: '2',
    ),
    _NavItem(
      '/employee/permission',
      'Permission',
      Icons.verified_user_outlined,
    ),
    _NavItem('/employee/extra-hours', 'Extra Hours', Icons.more_time_rounded),
    _NavItem('/employee/salary', 'Salary', Icons.currency_rupee_rounded),
    _NavItem('/employee/tracking', 'Tracking', Icons.location_on_rounded),
  ];

  @override
  Widget build(BuildContext context) => Container(
    width: 264,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: employeeLine)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Image.asset(
            'assets/images/godigital_logo.png',
            height: 67,
            alignment: Alignment.centerLeft,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF4FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: employeeBlue,
                  child: Text('AK', style: TextStyle(color: Colors.white)),
                ),
                SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Arul Kumar',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'EMP1001',
                      style: TextStyle(color: employeeBlue, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const _SectionLabel('MAIN'),
        ...items.take(6).map((item) => _SidebarTile(item: item, route: route)),
        const SizedBox(height: 8),
        const _SectionLabel('FINANCE'),
        _SidebarTile(item: items[6], route: route),
        const SizedBox(height: 8),
        const _SectionLabel('TOOLS'),
        _SidebarTile(item: items[7], route: route),
        const Spacer(),
        InkWell(
          onTap: () async {
            await AuthService().logout();
            if (!context.mounted) return;
            Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (_) => false,
            );
          },
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: Row(
              children: [
                Icon(Icons.logout_rounded, size: 17, color: employeeMuted),
                SizedBox(width: 8),
                Text('Logout', style: TextStyle(color: employeeMuted)),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 4, 22, 6),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF8390AA),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: .5,
      ),
    ),
  );
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({required this.item, required this.route});
  final _NavItem item;
  final String route;

  @override
  Widget build(BuildContext context) {
    final active = route == item.route;
    return InkWell(
      onTap: active ? null : () => Navigator.pushNamed(context, item.route),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEAF2FF) : null,
          border: Border(
            left: BorderSide(
              color: active ? employeeBlue : Colors.transparent,
              width: 4,
            ),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 19,
              color: active ? employeeBlue : const Color(0xFF50617F),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  color: active ? employeeBlue : const Color(0xFF34435E),
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (item.badge != null)
              CircleAvatar(
                radius: 11,
                backgroundColor: const Color(0xFFFFA000),
                child: Text(
                  item.badge!,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.route, this.label, this.icon, {this.badge});
  final String route;
  final String label;
  final IconData icon;
  final String? badge;
}

class EmployeeTopNavigation extends StatefulWidget {
  const EmployeeTopNavigation({super.key, required this.route, this.mobile = false});
  final String route;
  final bool mobile;

  @override
  State<EmployeeTopNavigation> createState() => _EmployeeTopNavigationState();
}

class _EmployeeTopNavigationState extends State<EmployeeTopNavigation> {
  Timer? _clockTimer;
  Timer? _pollingTimer;
  String _currentTime = '';
  bool _isCheckedIn = false;
  String _staffInitials = 'E';
  String _fullName = 'Employee';
  String _staffId = '';
  int _unreadNotifications = 1;
  List<Map<String, String>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _updateClock();
    _loadStoredIdentity();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateClock(),
    );
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _fetchHeaderStatus(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchProfile();
      _fetchHeaderStatus();
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _updateClock() {
    if (mounted) {
      setState(() {
        _currentTime = DateFormat('hh:mm a').format(DateTime.now());
      });
    }
  }

  void _applyIdentity(String? name, String? id) {
    final resolvedName = (name ?? '').trim();
    if (resolvedName.isEmpty) return;
    _fullName = resolvedName;
    _staffId = (id ?? '').trim().isEmpty ? 'EMP' : (id ?? '').trim();
    final parts = _fullName.split(RegExp(r'\s+'));
    _staffInitials = parts.length > 1
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : _fullName.substring(0, _fullName.length >= 2 ? 2 : 1).toUpperCase();
  }

  Future<void> _loadStoredIdentity() async {
    try {
      final raw = await AuthStorage.getString('user_data');
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw);
      if (data is Map && mounted) {
        setState(
          () => _applyIdentity(
            data['fullName']?.toString() ??
                data['full_name']?.toString() ??
                data['name']?.toString(),
            data['staffId']?.toString() ??
                data['staff_id']?.toString() ??
                data['employee_id']?.toString(),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _fetchProfile() async {
    final token =
        context.read<AuthService>().token ??
        await AuthStorage.getString('auth_token');
    if (token == null || token.isEmpty) return;
    try {
      final response = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/auth/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));
      final body = jsonDecode(response.body);
      if (response.statusCode != 200 ||
          body is! Map ||
          body['success'] != true ||
          body['data'] is! Map ||
          !mounted)
        return;
      final profile = Map<String, dynamic>.from(body['data'] as Map);
      setState(
        () => _applyIdentity(
          profile['fullName']?.toString() ?? profile['full_name']?.toString(),
          profile['staffId']?.toString() ?? profile['staff_id']?.toString(),
        ),
      );
    } catch (_) {}
  }

  Future<void> _fetchHeaderStatus() async {
    final token =
        context.read<AuthService>().token ??
        await AuthStorage.getString('auth_token');
    if (token == null) return;

    final configured = ApiConfig.baseUrl;
    final urls = ['$configured/attendance/header-status'];

    for (final raw in urls) {
      try {
        final res = await http
            .get(
              Uri.parse(raw),
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 3));

        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          if (body['success'] == true && mounted) {
            final data = body['data'];
            setState(() {
              _isCheckedIn = data['is_checked_in'] == true;
              _applyIdentity(
                data['full_name']?.toString(),
                data['staff_id']?.toString(),
              );
              _unreadNotifications = data['unread_count'] ?? 0;

              if (data['notifications'] is List) {
                _notifications = (data['notifications'] as List)
                    .map(
                      (item) => {
                        'title': item['title']?.toString() ?? '',
                        'subtitle': item['subtitle']?.toString() ?? '',
                      },
                    )
                    .toList();
              }
            });
            break;
          }
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mobile) {
      return Container(
        height: 78,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: employeeLine)),
          boxShadow: [
            BoxShadow(
              color: Color(0x0A07143F),
              blurRadius: 16,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Image.asset(
              'assets/images/godigital_logo.png',
              height: 45,
              width: 136,
              fit: BoxFit.contain,
            ),
            const Spacer(),
            EmployeeNotificationButton(
              unreadCount: _unreadNotifications,
              notifications: _notifications,
              onOpened: () => setState(() => _unreadNotifications = 0),
            ),
            const SizedBox(width: 12),
            EmployeeProfileMenu(
              radius: 25,
              initials: _staffInitials,
              fullName: _fullName,
              staffId: _staffId,
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 1120;
      return Container(
        height: 88,
        padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: employeeLine)),
          boxShadow: [
            BoxShadow(
              color: Color(0x0A07143F),
              blurRadius: 16,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Image.asset(
              'assets/images/godigital_logo.png',
              height: compact ? 50 : 60,
              width: compact ? 145 : 185,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
            ),
            SizedBox(width: compact ? 12 : 28),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
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
                      children: EmployeeSidebar.items
                          .map(
                            (item) => _TopNavigationItem(
                              item: item,
                              active: widget.route == item.route,
                              compact: compact,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: compact ? 12 : 24),
            if (!compact) ...[
              HeaderPill(_currentTime.isEmpty ? '08:46 AM' : _currentTime),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 5,
                      backgroundColor: employeeBlue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isCheckedIn ? 'Checked In' : 'Checked Out',
                      style: const TextStyle(
                        color: employeeBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
            ],
            EmployeeNotificationButton(
              unreadCount: _unreadNotifications,
              notifications: _notifications,
              onOpened: () => setState(() => _unreadNotifications = 0),
            ),
            const SizedBox(width: 10),
            EmployeeProfileMenu(
              radius: 21,
              initials: _staffInitials,
              fullName: _fullName,
              staffId: _staffId,
            ),
          ],
        ),
      );
    },
    );
  }
}

class _TopNavigationItem extends StatelessWidget {
  const _TopNavigationItem({
    required this.item,
    required this.active,
    required this.compact,
  });

  final _NavItem item;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Material(
      color: active ? employeeBlue : Colors.transparent,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: active ? null : () => Navigator.pushNamed(context, item.route),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 13 : 18,
            vertical: 12,
          ),
          child: Text(
            item.label,
            style: TextStyle(
              color: active ? Colors.white : employeeMuted,
              fontSize: compact ? 12 : 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    ),
  );
}

class HeaderPill extends StatelessWidget {
  const HeaderPill(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2FF),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(color: employeeBlue, fontWeight: FontWeight.w700),
    ),
  );
}

class EmployeeNotificationButton extends StatelessWidget {
  const EmployeeNotificationButton({
    super.key,
    this.compact = false,
    this.unreadCount = 0,
    this.notifications = const [],
    this.onOpened,
  });

  final bool compact;
  final int unreadCount;
  final List<Map<String, String>> notifications;
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      IconButton(
        tooltip: 'Notifications',
        onPressed: () {
          onOpened?.call();
          showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (_) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Notifications',
                      style: TextStyle(
                        color: employeeNavy,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (notifications.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          'No new notifications',
                          style: TextStyle(color: employeeMuted),
                        ),
                      )
                    else
                      ...notifications.map(
                        (n) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Color(0xFFEAF2FF),
                                child: Icon(
                                  Icons.notifications_active_outlined,
                                  color: employeeBlue,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      n['title'] ?? '',
                                      style: const TextStyle(
                                        color: employeeNavy,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      n['subtitle'] ?? '',
                                      style: const TextStyle(
                                        color: employeeMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFFF3F6FB),
          fixedSize: Size.square(compact ? 44 : 46),
          shape: const CircleBorder(),
        ),
        icon: const Icon(Icons.notifications_none_rounded, color: employeeNavy),
      ),
      if (unreadCount > 0)
        Positioned(
          top: 4,
          right: 4,
          child: Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: employeeBlue,
              shape: BoxShape.circle,
            ),
          ),
        ),
    ],
  );
}

class EmployeeProfileMenu extends StatelessWidget {
  const EmployeeProfileMenu({
    super.key,
    required this.radius,
    this.initials = 'E',
    this.fullName = 'Employee',
    this.staffId = '',
  });

  final double radius;
  final String initials;
  final String fullName;
  final String staffId;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Profile menu',
    offset: const Offset(0, 52),
    elevation: 8,
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    onSelected: (value) async {
      if (value == 'workspace') {
        await AuthService().logout();
        if (!context.mounted) return;
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      } else if (value == 'profile') {
        if (ModalRoute.of(context)?.settings.name != '/employee/profile') {
          Navigator.of(context).pushNamed('/employee/profile');
        }
      } else if (value == 'password') {
        await _showChangePasswordDialog(context);
      }
    },
    itemBuilder: (_) => [
      PopupMenuItem<String>(
        enabled: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fullName,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: employeeNavy,
              ),
            ),
            Text(
              staffId,
              style: const TextStyle(color: employeeBlue, fontSize: 12),
            ),
          ],
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem<String>(
        value: 'profile',
        child: Row(children: [
          Icon(Icons.person_outline, size: 18, color: employeeBlue),
          SizedBox(width: 10),
          Text('Profile settings', style: TextStyle(color: employeeBlue, fontWeight: FontWeight.w600)),
        ]),
      ),
      const PopupMenuItem<String>(
        value: 'password',
        child: Row(
          children: [
            Icon(Icons.lock_reset_outlined, size: 18, color: employeeBlue),
            SizedBox(width: 10),
            Text(
              'Change password',
              style: TextStyle(
                color: employeeBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      const PopupMenuItem<String>(
        value: 'workspace',
        child: Row(
          children: [
            Icon(Icons.logout_rounded, size: 18, color: employeeBlue),
            SizedBox(width: 10),
            Text(
              'Logout',
              style: TextStyle(
                color: employeeBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ],
    child: CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE8F0FF),
      child: Text(
        initials,
        style: TextStyle(
          color: employeeBlue,
          fontSize: radius * .72,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final username = TextEditingController();
    final current = TextEditingController();
    final updated = TextEditingController();
    var hidden = true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change password'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: username,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: current,
                  obscureText: hidden,
                  decoration: InputDecoration(
                    labelText: 'Current password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setDialogState(() => hidden = !hidden),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: updated,
                  obscureText: hidden,
                  decoration: const InputDecoration(
                    labelText: 'New password (minimum 8 characters)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final message = await context
                    .read<AuthService>()
                    .changePassword(
                      username: username.text,
                      currentPassword: current.text,
                      newPassword: updated.text,
                    );
                if (!dialogContext.mounted) return;
                if (message == null) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password updated.')),
                  );
                } else
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(message)));
              },
              child: const Text('Update password'),
            ),
          ],
        ),
      ),
    );
  }
}

class EmployeeCard extends StatelessWidget {
  const EmployeeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.color = Colors.white,
    this.borderColor = employeeLine,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: borderColor),
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0C174D9A),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: child,
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: employeeNavy,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                style: const TextStyle(color: employeeMuted, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    this.color = employeeBlue,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    style: FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    onPressed: onPressed ?? () {},
    icon: Icon(icon, size: 20),
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, this.color, {super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.caption,
  });

  final String label;
  final String value;
  final String? caption;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => EmployeeCard(
    padding: const EdgeInsets.all(20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: employeeMuted, fontSize: 12),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: const TextStyle(
                  color: employeeNavy,
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 4),
                Text(
                  caption!,
                  style: const TextStyle(color: employeeMuted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class LabeledValue extends StatelessWidget {
  const LabeledValue(
    this.label,
    this.value, {
    super.key,
    this.valueColor = employeeNavy,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: employeeMuted)),
        ),
        Text(
          value,
          style: TextStyle(color: valueColor, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.desktopColumns = 2,
    this.tabletColumns = 2,
    this.mobileColumns = 1,
    this.spacing = 18,
    this.childAspectRatio = 2.2,
  });

  final List<Widget> children;
  final int desktopColumns;
  final int tabletColumns;
  final int mobileColumns;
  final double spacing;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width < 600
        ? mobileColumns
        : width < 1024
        ? tabletColumns
        : desktopColumns;
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      childAspectRatio: childAspectRatio,
      children: children,
    );
  }
}

class SimpleTable extends StatelessWidget {
  const SimpleTable({
    super.key,
    required this.columns,
    required this.rows,
    this.minWidth = 760,
  });

  final List<String> columns;
  final List<List<Widget>> rows;
  final double minWidth;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SizedBox(
      width: minWidth,
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: const TableBorder(
          horizontalInside: BorderSide(color: employeeLine),
        ),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFF8FAFD)),
            children: columns
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.all(13),
                    child: Text(
                      c,
                      style: const TextStyle(
                        color: employeeMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          ...rows.map(
            (row) => TableRow(
              children: row
                  .map(
                    (cell) =>
                        Padding(padding: const EdgeInsets.all(13), child: cell),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    ),
  );
}

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.text, {super.key, this.color = employeeBlue});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(Icons.info_outline_rounded, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(color: color, height: 1.4)),
        ),
      ],
    ),
  );
}

class EmployeePageTitle extends StatelessWidget {
  const EmployeePageTitle({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: employeeNavy,
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      ?trailing,
    ],
  );
}

class MobileEmployeeHeader extends StatelessWidget {
  const MobileEmployeeHeader({super.key, this.showGreeting = true});
  final bool showGreeting;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // EmployeeScaffold already provides the logo, notifications and profile.
      // Page content only needs the optional greeting.
      if (showGreeting) ...[
        Consumer<AuthService>(
          builder: (_, auth, __) {
            final name =
                (auth.user?['fullName'] ?? auth.user?['name'] ?? 'Employee')
                    .toString()
                    .trim();
            return Text(
              'Hello, ${name.isEmpty ? 'Employee' : name}',
              style: const TextStyle(color: Color(0xFF495572), fontSize: 19),
            );
          },
        ),
      ],
    ],
  );
}
