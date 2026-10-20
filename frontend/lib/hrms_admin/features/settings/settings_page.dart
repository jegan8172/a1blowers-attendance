import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/admin_appearance.dart';
import '../dashboard/dashboard_page.dart';
import '../employees/employees_page.dart';
import '../payroll/payroll_page.dart';
import '../tracking/tracking_page.dart';
import '../../shared/widgets/admin_top_nav.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  static Widget builder(BuildContext context) => const SettingsPage();

  Future<void> _open(BuildContext context, String route, String action) {
    final Widget destination = switch (route) {
      '/admin/dashboard' => DashboardPage(settingsAction: action, inSettingsDialog: true),
      '/admin/employees' => EmployeesPage(settingsAction: action, inSettingsDialog: true),
      '/admin/payroll' => PayrollPage(settingsAction: action, inSettingsDialog: true),
      '/admin/tracking' => TrackingPage(settingsAction: action, inSettingsDialog: true),
      _ => const SizedBox.shrink(),
    };
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(width: 1280, height: 760, child: destination),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AdminAppearanceController>();
    final colors = _SettingsPalette.of(context, appearance);
    final mobile = MediaQuery.sizeOf(context).width < 720;
    final wide = MediaQuery.sizeOf(context).width >= 1180;
    final categories = [
      _SettingsGroup('Work time', 'Schedules, working days and calendar rules', Icons.calendar_month_rounded, [
        _SettingsAction('Manage time', 'Configure shifts and working hours', Icons.schedule_outlined, () => _open(context, '/admin/dashboard', 'manageTime')),
        _SettingsAction('Manage calendar', 'Holidays and company calendar', Icons.edit_calendar_outlined, () => _open(context, '/admin/dashboard', 'manageCalendar')),
      ]),
      _SettingsGroup('Employees', 'Employee access and people policies', Icons.groups_outlined, [
        _SettingsAction('Device requests', 'Review registered devices', Icons.phonelink_lock_outlined, () => _open(context, '/admin/employees', 'deviceRequests')),
        _SettingsAction('Leave policy', 'Leave rules and balances', Icons.event_available_outlined, () => _open(context, '/admin/employees', 'leavePolicy')),
        _SettingsAction('Add employee', 'Create an employee profile', Icons.person_add_alt_1_outlined, () => _open(context, '/admin/employees', 'addEmployee'), emphasized: true),
      ]),
      _SettingsGroup('Payroll', 'Pay cycles, salary and weekly-off schedules', Icons.account_balance_wallet_outlined, [
        _SettingsAction('Payroll policy', 'Working days and deductions', Icons.receipt_long_outlined, () => _open(context, '/admin/payroll', 'payrollPolicy')),
        _SettingsAction('Weekly off templates', 'Assign weekly off schedules', Icons.calendar_view_week_outlined, () => _open(context, '/admin/weekly-off-templates', 'weeklyOffTemplates')),
      ]),
      _SettingsGroup('Live tracking', 'Locations and field activity controls', Icons.location_on_outlined, [
        _SettingsAction('Office locations', 'Manage office check-in locations', Icons.business_outlined, () => _open(context, '/admin/tracking', 'officeLocation')),
        _SettingsAction('Tracking settings', 'GPS interval, radius and waiting rules', Icons.timer_outlined, () => _open(context, '/admin/tracking', 'trackingSettings')),
      ]),
      _SettingsGroup('Reminders', 'Clock-out reminders and notification preferences', Icons.notifications_active_outlined, [
        _SettingsAction('Clock-out reminders', 'Timing, sound and repeat reminders', Icons.alarm_outlined, () => _open(context, '/admin/tracking', 'clockOutReminderSettings')),
        _SettingsAction('Notification settings', 'Choose how alerts are delivered', Icons.tune_rounded, () => showAdminNotificationSettings(context)),
      ]),
    ];
    final columns = mobile ? 1 : wide ? 3 : 2;
    return Scaffold(
      backgroundColor: colors.page,
      bottomNavigationBar: mobile ? const AdminMobileBottomNav(activeRoute: '/admin/settings') : null,
      body: Column(children: [
        const AdminTopNav(activeRoute: '/admin/settings'),
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(mobile ? 16 : 32, 26, mobile ? 16 : 32, 34),
          child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1500),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _SettingsHeading(colors: colors),
              const SizedBox(height: 22),
              _AppearancePanel(colors: colors),
              const SizedBox(height: 24),
              Text('Workspace settings', style: TextStyle(color: colors.ink, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Choose a section to manage your organisation settings.', style: TextStyle(color: colors.muted, fontSize: 14)),
              const SizedBox(height: 15),
              LayoutBuilder(builder: (_, box) {
                final gap = 16.0;
                final width = (box.maxWidth - (columns - 1) * gap) / columns;
                return Wrap(spacing: gap, runSpacing: gap, children: categories.map((group) => SizedBox(width: width, child: _SettingsGroupCard(group: group, colors: colors))).toList());
              }),
            ]),
          )),
        )),
      ]),
    );
  }
}

class _SettingsHeading extends StatelessWidget {
  const _SettingsHeading({required this.colors});
  final _SettingsPalette colors;
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 48, height: 48, decoration: BoxDecoration(color: colors.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.tune_rounded, color: colors.accent, size: 27)),
    const SizedBox(width: 14),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Settings', style: TextStyle(color: colors.ink, fontSize: 31, fontWeight: FontWeight.w800, height: 1.05)),
      const SizedBox(height: 5),
      Text('Control policies, alerts, tracking, and workspace preferences.', style: TextStyle(color: colors.muted, fontSize: 14)),
    ])),
  ]);
}

class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel({required this.colors});
  final _SettingsPalette colors;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: colors.surface, border: Border.all(color: colors.border), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: colors.ink.withValues(alpha: .05), blurRadius: 18, offset: const Offset(0, 6))]),
    child: Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: colors.accent.withValues(alpha: .13), borderRadius: BorderRadius.circular(13)), child: Icon(Icons.palette_outlined, color: colors.accent)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Appearance', style: TextStyle(color: colors.ink, fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text('Your workspace uses the standard GoDigital light theme and brand colours.', style: TextStyle(color: colors.muted, fontSize: 13))])),
      ]),
  );
}

class _SettingsGroup {
  const _SettingsGroup(this.title, this.description, this.icon, this.actions);
  final String title, description;
  final IconData icon;
  final List<_SettingsAction> actions;
}

class _SettingsAction {
  const _SettingsAction(this.title, this.subtitle, this.icon, this.onTap, {this.emphasized = false});
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool emphasized;
}

class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({required this.group, required this.colors});
  final _SettingsGroup group;
  final _SettingsPalette colors;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: colors.surface, border: Border.all(color: colors.border), borderRadius: BorderRadius.circular(15)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: colors.accent.withValues(alpha: .11), borderRadius: BorderRadius.circular(11)), child: Icon(group.icon, color: colors.accent, size: 21)),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(group.title, style: TextStyle(color: colors.ink, fontWeight: FontWeight.w800, fontSize: 17)), const SizedBox(height: 2), Text(group.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.muted, fontSize: 11))])),
      ]),
      const SizedBox(height: 14),
      ...group.actions.map((action) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _SettingsActionTile(action: action, colors: colors))),
    ]),
  );
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({required this.action, required this.colors});
  final _SettingsAction action;
  final _SettingsPalette colors;
  @override
  Widget build(BuildContext context) => Material(color: Colors.transparent, child: InkWell(
    onTap: action.onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(color: action.emphasized ? colors.accent : colors.tile, border: Border.all(color: action.emphasized ? colors.accent : colors.border), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(action.icon, size: 19, color: action.emphasized ? Colors.white : colors.accent),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(action.title, style: TextStyle(color: action.emphasized ? Colors.white : colors.ink, fontWeight: FontWeight.w700, fontSize: 13)), const SizedBox(height: 2), Text(action.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: action.emphasized ? Colors.white.withValues(alpha: .84) : colors.muted, fontSize: 11))])),
        Icon(Icons.arrow_forward_ios_rounded, size: 14, color: action.emphasized ? Colors.white : colors.muted),
      ]),
    ),
  ));
}

class _SettingsPalette {
  const _SettingsPalette({required this.accent, required this.page, required this.surface, required this.tile, required this.ink, required this.muted, required this.border});
  final Color accent, page, surface, tile, ink, muted, border;
  static _SettingsPalette of(BuildContext context, AdminAppearanceController appearance) {
    return _SettingsPalette(
      accent: appearance.accent,
      page: const Color(0xFFF7F9FD),
      surface: Colors.white,
      tile: const Color(0xFFF9FBFE),
      ink: const Color(0xFF102653),
      muted: const Color(0xFF647493),
      border: const Color(0xFFE1E7F0),
    );
  }
}
