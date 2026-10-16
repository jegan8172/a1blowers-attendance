import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/api_config.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/hrms_notifications_api.dart';
import '../../../services/auth_service.dart';
import '../../../screens/login_screen.dart';

const _blue = Color(0xFFE3162A);
const _navy = Color(0xFF081B3C);

/// Opens the same notification preferences dialog used by the notification bell.
Future<void> showAdminNotificationSettings(BuildContext context) async {
  final player = AudioPlayer();
  try {
    final data = await HrmsNotificationsApi.list();
    final settings = data['settings'] is Map
        ? Map<String, dynamic>.from(data['settings'] as Map)
        : const <String, dynamic>{};
    await showDialog<bool>(
      context: context,
      builder: (_) => _NotificationSettingsDialog(
        settings: settings,
        onPreview: (name, volume, customUrl) {
          final source =
              name == 'custom' && customUrl != null && customUrl.isNotEmpty
              ? UrlSource(ApiConfig.mediaUrl(customUrl))
              : AssetSource('sounds/$name');
          return player.play(source, volume: volume.clamp(0.0, 1.0).toDouble());
        },
      ),
    );
  } finally {
    await player.dispose();
  }
}

class AdminTopNav extends StatelessWidget {
  const AdminTopNav({
    super.key,
    required this.activeRoute,
  });

  final String activeRoute;

  static const items = <(String, String)>[
    ('Dashboard', '/admin/dashboard'),
    ('Employees', '/admin/employees'),
    ('Clock Logs', '/admin/clock-logs'),
    ('Approvals', '/admin/approvals'),
    ('Payroll', '/admin/payroll'),
    ('Tracking', '/admin/tracking'),
    ('Settings', '/admin/settings'),
  ];

  void _open(BuildContext context, String route) {
    if (route == activeRoute) return;
    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final mobile = screenWidth < 600;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final navSurface = Theme.of(context).colorScheme.surface;
    // The full navigation pill needs considerably more room than the page
    // content. Switch to a compact menu before Windows display scaling can
    // squeeze the trailing actions outside the viewport.
    final compact = screenWidth < 1320;
    return Container(
      // Compact desktop height keeps the attendance sheet above the fold on
      // Windows displays using common browser scaling.
      height: mobile ? 70 : 64,
      padding: EdgeInsets.symmetric(
        horizontal: mobile
            ? 14
            : compact
            ? 16
            : 20,
      ),
      decoration: BoxDecoration(
        color: dark ? navSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x12071A72),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          dark
              ? ColorFiltered(
                  // The source artwork has a white baked-in rectangle. This
                  // maps that white to the current navigation surface while
                  // retaining a light wordmark and a red A1 symbol.
                  colorFilter: ColorFilter.matrix(<double>[
                    0, -.5, -.5, 0, 255.0 + navSurface.red.toDouble(),
                    -1, .5, -.5, 0, 255.0 + navSurface.green.toDouble(),
                    -1, -.5, .5, 0, 255.0 + navSurface.blue.toDouble(),
                    0, 0, 0, 1, 0,
                  ]),
                  child: Image.asset(
                    'assets/images/a1_blowers_logo_header.png',
                    width: mobile ? 118 : compact ? 142 : 174,
                    height: mobile ? 42 : 48,
                    fit: BoxFit.contain,
                  ),
                )
              : Image.asset(
                  'assets/images/a1_blowers_logo_header.png',
                  width: mobile ? 118 : compact ? 142 : 174,
                  height: mobile ? 42 : 48,
                  fit: BoxFit.contain,
                ),
          SizedBox(width: mobile ? 8 : 14),
          if (!compact)
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _DesktopNav(
                    activeRoute: activeRoute,
                    onOpen: (route) => _open(context, route),
                    light: dark,
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          if (compact && !mobile)
            _AdminNavMenu(
              activeRoute: activeRoute,
              onOpen: (route) => _open(context, route),
            ),
          if (compact && !mobile) const SizedBox(width: 8),
          AdminNotificationBell(mobile: mobile),
          const SizedBox(width: 8),
          const AdminAccountButton(),
          SizedBox(
            width: mobile
                ? 3
                : compact
                ? 8
                : 18,
          ),
          AdminLogoutButton(compact: compact || mobile),
        ],
      ),
    );
  }
}

class _AdminNavMenu extends StatelessWidget {
  const _AdminNavMenu({required this.activeRoute, required this.onOpen});

  final String activeRoute;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final activeLabel = AdminTopNav.items
        .firstWhere(
          (item) => item.$2 == activeRoute,
          orElse: () => ('Menu', ''),
        )
        .$1;
    return PopupMenuButton<String>(
      tooltip: 'Admin navigation',
      onSelected: onOpen,
      itemBuilder: (_) => AdminTopNav.items
          .map(
            (item) => PopupMenuItem<String>(
              value: item.$2,
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: item.$2 == activeRoute
                        ? const Icon(
                            Icons.check_rounded,
                            color: _blue,
                            size: 19,
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(item.$1),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F8),
          border: Border.all(color: const Color(0xFFF1C5CA)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_rounded, color: _navy, size: 21),
            const SizedBox(width: 8),
            Text(
              activeLabel,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: _navy,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class AdminLogoutButton extends StatelessWidget {
  const AdminLogoutButton({super.key, this.compact = false});

  final bool compact;

  Future<void> _logout(BuildContext context) async {
    // Use the app's provided service instead of constructing a separate
    // instance. The provider must be notified so AuthGate switches to login.
    await context.read<AuthService>().logout();
    if (context.mounted) {
      // AdminPortalApp is a nested MaterialApp, so '/' would resolve back to
      // the admin dashboard. Replace the whole visible stack with login.
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFF4F7FC) : _navy;
    if (compact) {
      return IconButton(
        tooltip: 'Logout',
        onPressed: () => _logout(context),
        style: IconButton.styleFrom(
          minimumSize: const Size(42, 42),
          backgroundColor: dark ? const Color(0xFF29354A) : const Color(0xFFFFEEF0),
          foregroundColor: foreground,
          shape: const CircleBorder(),
        ),
        icon: const Icon(Icons.logout_rounded, size: 21),
      );
    }
    return TextButton.icon(
      onPressed: () => _logout(context),
      icon: const Icon(Icons.logout_rounded, size: 19),
      label: const Text('Logout'),
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: dark ? const Color(0xFF536176) : const Color(0xFFD6E0F0)),
        ),
      ),
    );
  }
}

class AdminAccountButton extends StatelessWidget {
  const AdminAccountButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Change username or password',
    onPressed: () => _showDialog(context),
    icon: Icon(Icons.manage_accounts_outlined, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF4F7FC) : _navy),
  );

  Future<void> _showDialog(BuildContext context) async {
    final auth = context.read<AuthService>();
    final currentUsername = TextEditingController(
      text: auth.user?['username']?.toString() ?? '',
    );
    final newUsername = TextEditingController();
    final currentPassword = TextEditingController();
    final newPassword = TextEditingController();
    var hidden = true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Admin account credentials'),
          content: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentUsername,
                  decoration: const InputDecoration(
                    labelText: 'Current username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: currentPassword,
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
                  controller: newUsername,
                  decoration: const InputDecoration(
                    labelText: 'New username (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPassword,
                  obscureText: hidden,
                  decoration: const InputDecoration(
                    labelText: 'New password (optional, minimum 8)',
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
                final message = await auth.changePassword(
                  username: currentUsername.text,
                  currentPassword: currentPassword.text,
                  newPassword: newPassword.text,
                  newUsername: newUsername.text,
                );
                if (!dialogContext.mounted) return;
                if (message == null) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Admin credentials updated. Use the new details at your next login.',
                      ),
                    ),
                  );
                } else
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(message)));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared floating dock for every admin page below the mobile breakpoint.
/// Less-frequent destinations remain available from the hamburger drawer.
class AdminMobileBottomNav extends StatelessWidget {
  const AdminMobileBottomNav({super.key, required this.activeRoute});

  final String activeRoute;

  void _open(BuildContext context, String route) {
    if (route == activeRoute) return;
    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 600) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF081B3C),
          borderRadius: BorderRadius.circular(34),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            _dockItem(
              context,
              icon: Icons.home_rounded,
              label: 'Dashboard',
              route: '/admin/dashboard',
            ),
            _dockItem(
              context,
              icon: Icons.groups_rounded,
              label: 'Employees',
              route: '/admin/employees',
            ),
            _dockItem(
              context,
              icon: Icons.history_rounded,
              label: 'Clock Logs',
              route: '/admin/clock-logs',
            ),
            _dockItem(
              context,
              icon: Icons.task_alt_rounded,
              label: 'Approvals',
              route: '/admin/approvals',
            ),
            _dockItem(
              context,
              icon: Icons.account_balance_wallet_rounded,
              label: 'Payroll',
              route: '/admin/payroll',
            ),
            _dockItem(
              context,
              icon: Icons.location_on_rounded,
              label: 'Tracking',
              route: '/admin/tracking',
            ),
            _dockItem(
              context,
              icon: Icons.settings_rounded,
              label: 'Settings',
              route: '/admin/settings',
            ),
          ],
        ),
      ),
    );
  }

  Widget _dockItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String route,
  }) {
    final active = activeRoute == route;
    return Expanded(
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: () => _open(context, route),
          borderRadius: BorderRadius.circular(25),
          child: Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: active ? _blue : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    super.key,
    required this.title,
    this.breadcrumb,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? breadcrumb;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 31,
              height: 1.15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          subtitle != null
              ? Text(
                  subtitle!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 15,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Home',
                      style: TextStyle(color: _blue, fontSize: 15),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(Icons.chevron_right, color: _blue, size: 18),
                    ),
                    Text(
                      breadcrumb ?? title,
                      style: const TextStyle(color: _blue, fontSize: 15),
                    ),
                  ],
                ),
        ],
      );
      if (trailing == null) return heading;
      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, const SizedBox(height: 14), trailing!],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: heading),
          trailing!,
        ],
      );
    },
  );
}

class _DesktopNav extends StatelessWidget {
  const _DesktopNav({
    required this.activeRoute,
    required this.onOpen,
    this.light = false,
  });
  final String activeRoute;
  final ValueChanged<String> onOpen;
  final bool light;

  IconData _iconFor(String route) => switch (route) {
    '/admin/dashboard' => Icons.grid_view_rounded,
    '/admin/employees' => Icons.groups_2_outlined,
    '/admin/clock-logs' => Icons.calendar_month_outlined,
    '/admin/approvals' => Icons.fact_check_outlined,
    '/admin/payroll' => Icons.account_balance_wallet_outlined,
    '/admin/tracking' => Icons.location_on_outlined,
    _ => Icons.settings_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
    children: AdminTopNav.items.map((item) {
      final active = item.$2 == activeRoute;
      return InkWell(
        onTap: () => onOpen(item.$2),
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: active ? accent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconFor(item.$2),
                size: 18,
                color: active ? accent : (light ? Colors.white : _navy),
              ),
              const SizedBox(width: 7),
              Text(
                item.$1,
                style: TextStyle(
                  color: active ? accent : (light ? Colors.white : _navy),
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList(),
  );
  }
}

class AdminNotificationBell extends StatefulWidget {
  const AdminNotificationBell({super.key, required this.mobile});
  final bool mobile;

  @override
  State<AdminNotificationBell> createState() => _AdminNotificationBellState();
}

class _AdminNotificationBellState extends State<AdminNotificationBell> {
  Timer? _timer;
  int _unreadCount = 0;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await HrmsNotificationsApi.list();
      if (!mounted) return;
      setState(() {
        _unreadCount = (data['unreadCount'] as num?)?.toInt() ?? 0;
        _items = ((data['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _open() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _NotificationsDialog(
        items: _items,
        unreadCount: _unreadCount,
        onMarkAllRead: () async {
          await HrmsNotificationsApi.markAllRead();
          if (!mounted) return;
          setState(() => _unreadCount = 0);
          if (dialogContext.mounted) Navigator.pop(dialogContext);
        },
        onViewApprovals: () {
          Navigator.pop(dialogContext);
          Navigator.pushReplacementNamed(context, '/admin/approvals');
        },
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Notifications',
    onPressed: _open,
    style: IconButton.styleFrom(
      minimumSize: Size(widget.mobile ? 38 : 45, widget.mobile ? 38 : 45),
      backgroundColor: widget.mobile ? const Color(0xFFF3F6FC) : Colors.white,
      side: const BorderSide(color: Color(0xFFE2E7F1)),
    ),
    icon: Badge(
      isLabelVisible: _unreadCount > 0,
      label: Text(_unreadCount > 99 ? '99+' : '$_unreadCount'),
      backgroundColor: _blue,
      child: Icon(
        Icons.notifications_none_rounded,
        color: _navy,
        size: widget.mobile ? 22 : 24,
      ),
    ),
  );
}

class _NotificationsDialog extends StatelessWidget {
  const _NotificationsDialog({
    required this.items,
    required this.unreadCount,
    required this.onMarkAllRead,
    required this.onViewApprovals,
  });

  final List<Map<String, dynamic>> items;
  final int unreadCount;
  final Future<void> Function() onMarkAllRead;
  final VoidCallback onViewApprovals;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Icon(Icons.notifications_rounded, color: _blue),
        const SizedBox(width: 9),
        const Expanded(child: Text('Notifications')),
        TextButton(
          onPressed: unreadCount == 0 ? null : onMarkAllRead,
          child: const Text('Mark all as read'),
        ),
      ],
    ),
    content: SizedBox(
      width: 420,
      child: items.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No approval notifications.')),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final item = items[index];
                  final unread = item['isRead'] != true;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: unread
                          ? const Color(0xFFEAF2FF)
                          : const Color(0xFFF3F5F9),
                      child: Icon(
                        Icons.assignment_rounded,
                        color: unread ? _blue : const Color(0xFF63718F),
                      ),
                    ),
                    title: Text(
                      item['title']?.toString() ?? 'Approval request',
                      style: TextStyle(
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      item['message']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
    ),
    actions: [
      OutlinedButton.icon(
        onPressed: onViewApprovals,
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        label: const Text('View Approvals'),
      ),
    ],
  );
}

class _NotificationSettingsDialog extends StatefulWidget {
  const _NotificationSettingsDialog({
    required this.settings,
    required this.onPreview,
  });
  final Map<String, dynamic> settings;
  final Future<void> Function(
    String soundName,
    double volume,
    String? customUrl,
  )
  onPreview;

  @override
  State<_NotificationSettingsDialog> createState() =>
      _NotificationSettingsDialogState();
}

class _NotificationSettingsDialogState
    extends State<_NotificationSettingsDialog> {
  late bool _soundEnabled;
  late bool _commentsEnabled;
  late bool _waitingEnabled;
  late String _soundName;
  String? _customSoundUrl;
  String? _customSoundLabel;
  late double _volume;
  bool _saving = false;
  bool _uploading = false;

  static const _sounds = <String>[
    'notification.mp3',
    'notifications.mp3',
    'notificationss.mp3',
    'notification_ai voice.mp3',
  ];

  @override
  void initState() {
    super.initState();
    _soundEnabled = widget.settings['soundEnabled'] != false;
    _commentsEnabled = widget.settings['commentNotificationsEnabled'] != false;
    _waitingEnabled =
        widget.settings['waitingReasonNotificationsEnabled'] != false;
    _soundName = _sounds.contains(widget.settings['soundName'])
        ? widget.settings['soundName'] as String
        : (widget.settings['soundName'] == 'custom' &&
                  widget.settings['customSoundUrl'] != null
              ? 'custom'
              : _sounds.first);
    _customSoundUrl = widget.settings['customSoundUrl']?.toString();
    _customSoundLabel = _customSoundUrl == null
        ? null
        : 'Custom uploaded sound';
    final requestedVolume =
        (widget.settings['soundVolume'] as num?)?.toDouble() ?? 70;
    _volume = requestedVolume < 0
        ? 0
        : (requestedVolume > 100 ? 100 : requestedVolume);
  }

  List<String> get _soundOptions => <String>[
    ..._sounds,
    if (_customSoundUrl != null) 'custom',
  ];

  Future<void> _uploadSound() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'm4a', 'aac', 'ogg'],
      withData: true,
    );
    final file = selection != null && selection.files.isNotEmpty
        ? selection.files.first
        : null;
    if (file == null) return;
    if (file.bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the selected file.')),
        );
      }
      return;
    }
    if (file.bytes!.length > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Choose an audio file smaller than 5 MB.'),
          ),
        );
      }
      return;
    }
    setState(() => _uploading = true);
    try {
      final settings = await HrmsNotificationsApi.uploadCustomSound(
        file.bytes!,
        file.name,
      );
      if (!mounted) return;
      setState(() {
        _customSoundUrl = settings['customSoundUrl']?.toString();
        _customSoundLabel = file.name;
        _soundName = 'custom';
      });
      await widget.onPreview('custom', _volume / 100, _customSoundUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Custom sound uploaded and selected.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await HrmsNotificationsApi.updateSettings({
        'soundEnabled': _soundEnabled,
        'soundName': _soundName,
        'soundVolume': _volume.round(),
        'commentNotificationsEnabled': _commentsEnabled,
        'waitingReasonNotificationsEnabled': _waitingEnabled,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Notification settings'),
    content: SizedBox(
      width: 390,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Play a sound for new alerts'),
            value: _soundEnabled,
            onChanged: (value) => setState(() => _soundEnabled = value),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(_soundName),
            initialValue: _soundName,
            decoration: const InputDecoration(labelText: 'Notification sound'),
            items: _soundOptions
                .map(
                  (sound) => DropdownMenuItem(
                    value: sound,
                    child: Text(
                      sound == 'custom'
                          ? (_customSoundLabel ?? 'Custom uploaded sound')
                          : sound.replaceAll('.mp3', '').replaceAll('_', ' '),
                    ),
                  ),
                )
                .toList(),
            onChanged: _soundEnabled
                ? (value) => setState(() => _soundName = value!)
                : null,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _uploading ? null : _uploadSound,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: Text(_uploading ? 'Uploading...' : 'Upload custom sound'),
            ),
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'MP3, WAV, M4A, AAC, or OGG · maximum 5 MB',
                style: TextStyle(fontSize: 12, color: Color(0xFF63718F)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Volume'),
              Expanded(
                child: Slider(
                  value: _volume,
                  min: 0,
                  max: 100,
                  divisions: 10,
                  label: '${_volume.round()}%',
                  onChanged: _soundEnabled
                      ? (value) => setState(() => _volume = value)
                      : null,
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _soundEnabled
                  ? () => widget.onPreview(
                      _soundName,
                      _volume / 100,
                      _customSoundUrl,
                    )
                  : null,
              icon: const Icon(Icons.volume_up_outlined, size: 18),
              label: const Text('Preview sound'),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Employee comments'),
            value: _commentsEnabled,
            onChanged: (value) => setState(() => _commentsEnabled = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Field waiting reasons'),
            value: _waitingEnabled,
            onChanged: (value) => setState(() => _waitingEnabled = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving...' : 'Save settings'),
      ),
    ],
  );
}
