import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../services/hrms_dashboard_api.dart';

const _blue = Color(0xFF1769E0);
const _navy = Color(0xFF081B3C);
const _line = Color(0xFFD8E1F1);
const _green = Color(0xFF138B2B);
const _purple = Color(0xFF8500C8);
const _off = Color(0xFF63718F);

abstract final class HrmsColors {
  static const blue = _blue;
  static const navy = _navy;
  static const line = _line;
}

class CalendarStore {
  static const weeklyOffKey = 'admin_calendar_weekly_off';
  static const overridesKey = 'admin_calendar_overrides';
  static const notificationsKey = 'employee_calendar_notifications';

  static Future<int> loadWeeklyOff() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(weeklyOffKey) ?? DateTime.sunday;
  }

  static Future<List<Map<String, dynamic>>> loadOverrides() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(overridesKey);
    if (encoded == null || encoded.isEmpty) return [];
    final decoded = jsonDecode(encoded) as List<dynamic>;
    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static Future<void> saveWeeklyOff(int weekday) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(weeklyOffKey, weekday);
  }

  static Future<void> saveOverrides(
    List<Map<String, dynamic>> overrides,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(overridesKey, jsonEncode(overrides));
  }

  static Future<List<Map<String, dynamic>>> loadNotifications() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(notificationsKey);
    if (encoded == null || encoded.isEmpty) return [];
    final decoded = jsonDecode(encoded) as List<dynamic>;
    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static Future<void> addNotification(Map<String, dynamic> notification) async {
    final preferences = await SharedPreferences.getInstance();
    final notifications = await loadNotifications();
    notifications.add(notification);
    await preferences.setString(notificationsKey, jsonEncode(notifications));
  }
}

Future<bool> showManageCalendarDialog(BuildContext context) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: const Color(0xA607163E),
    builder: (_) => const ManageCalendarDialog(),
  );
  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Calendar override saved successfully')),
    );
  }
  return saved == true;
}

class ManageCalendarDialog extends StatefulWidget {
  const ManageCalendarDialog({super.key});

  @override
  State<ManageCalendarDialog> createState() => _ManageCalendarDialogState();
}

class _ManageCalendarDialogState extends State<ManageCalendarDialog> {
  late DateTime visibleMonth;
  late int selectedDay;
  int weeklyOffDay = DateTime.sunday;
  String selectedStatus = 'Working Day';
  String scope = 'All Employees';
  bool recalculate = true;
  bool notifyEmployees = true;
  List<Map<String, dynamic>> overrides = [];
  final reasonController = TextEditingController(text: 'Special working day');

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    visibleMonth = DateTime(today.year, today.month);
    selectedDay = today.day;
    _loadCalendar();
  }

  Future<void> _loadCalendar() async {
    var loadedWeeklyOff = await CalendarStore.loadWeeklyOff();
    var loadedOverrides = await CalendarStore.loadOverrides();
    try {
      final data = await HrmsDashboardApi.calendarSettings();
      final days = (data['weeklyOffDays'] as List? ?? [])
          .map((day) => int.parse('$day'))
          .toList();
      if (days.isNotEmpty)
        loadedWeeklyOff = days.first == 0 ? DateTime.sunday : days.first;
      // The server is authoritative. Opening the calendar must not write old
      // browser-cache entries back over newer production settings.
      loadedOverrides = (data['overrides'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      await CalendarStore.saveOverrides(loadedOverrides);
    } catch (_) {
      // Retain cached data, but do not present it as confirmed server state.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not load the server calendar. Showing cached settings; totals may be outdated.',
            ),
          ),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      weeklyOffDay = loadedWeeklyOff;
      overrides = loadedOverrides;
    });
  }

  @override
  void dispose() {
    reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 800;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 32,
        vertical: 18,
      ),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 916, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DialogHeader(onClose: () => Navigator.pop(context)),
              const SizedBox(height: 18),
              _DefaultWeeklyOff(
                day: _weekdayName(weeklyOffDay),
                onEdit: _showEditDefault,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F7FF),
                  border: Border.all(color: _line),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_outlined, color: _blue),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total working days',
                            style: TextStyle(
                              color: _navy,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'For the displayed month · saved calendar rules',
                            style: TextStyle(color: _off, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$_totalWorkingDays',
                      style: const TextStyle(
                        color: _blue,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (compact) ...[
                _CalendarPanel(
                  month: visibleMonth,
                  selectedDay: selectedDay,
                  onPrevious: _previousMonth,
                  onNext: _nextMonth,
                  weeklyOffDay: weeklyOffDay,
                  statusForDate: _calendarStatusFor,
                  actualStatusForDate: _statusFor,
                  onSelected: (day) => setState(() => selectedDay = day),
                ),
                const SizedBox(height: 12),
                _EditDatePanel(
                  selectedDay: selectedDay,
                  month: visibleMonth,
                  status: selectedStatus,
                  currentStatus: _statusFor(_selectedDate),
                  scope: scope,
                  recalculate: recalculate,
                  notifyEmployees: notifyEmployees,
                  reasonController: reasonController,
                  onStatusChanged: (value) =>
                      setState(() => selectedStatus = value!),
                  onScopeChanged: (value) => setState(() => scope = value),
                  onRecalculateChanged: (value) =>
                      setState(() => recalculate = value),
                  onNotifyChanged: (value) =>
                      setState(() => notifyEmployees = value),
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _CalendarPanel(
                        month: visibleMonth,
                        selectedDay: selectedDay,
                        onPrevious: _previousMonth,
                        onNext: _nextMonth,
                        weeklyOffDay: weeklyOffDay,
                        statusForDate: _calendarStatusFor,
                        actualStatusForDate: _statusFor,
                        onSelected: (day) => setState(() => selectedDay = day),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 4,
                      child: _EditDatePanel(
                        selectedDay: selectedDay,
                        month: visibleMonth,
                        status: selectedStatus,
                        currentStatus: _statusFor(_selectedDate),
                        scope: scope,
                        recalculate: recalculate,
                        notifyEmployees: notifyEmployees,
                        reasonController: reasonController,
                        onStatusChanged: (value) =>
                            setState(() => selectedStatus = value!),
                        onScopeChanged: (value) =>
                            setState(() => scope = value),
                        onRecalculateChanged: (value) =>
                            setState(() => recalculate = value),
                        onNotifyChanged: (value) =>
                            setState(() => notifyEmployees = value),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 18),
              _DialogFooter(
                compact: compact,
                onHistory: _showHistory,
                onCancel: () => Navigator.pop(context),
                onSave: _saveOverride,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _previousMonth() {
    setState(() {
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month - 1);
      selectedDay = 1;
    });
  }

  DateTime get _selectedDate =>
      DateTime(visibleMonth.year, visibleMonth.month, selectedDay);

  int get _totalWorkingDays {
    final days = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    var total = 0;
    for (var day = 1; day <= days; day++) {
      if (_statusFor(DateTime(visibleMonth.year, visibleMonth.month, day)) ==
          'Working Day') {
        total++;
      }
    }
    return total;
  }

  String _statusFor(DateTime date) {
    final key = _dateKey(date);
    final existing = overrides.where((item) => item['date'] == key).toList();
    if (existing.isNotEmpty) return existing.last['status'] as String;
    return date.weekday == weeklyOffDay ? 'Weekly Off' : 'Working Day';
  }

  String _calendarStatusFor(DateTime date) {
    final key = _dateKey(date);
    final existing = overrides.where((item) => item['date'] == key).toList();
    if (existing.isEmpty) return _statusFor(date);
    final savedStatus = existing.last['status'] as String;
    return savedStatus == 'Holiday' ? 'Holiday' : 'Override';
  }

  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _weekdayName(int weekday) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][weekday - 1];

  void _nextMonth() {
    setState(() {
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + 1);
      selectedDay = 1;
    });
  }

  Future<void> _showEditDefault() async {
    var chosenDay = weeklyOffDay;
    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Default Weekly Off'),
        content: StatefulBuilder(
          builder: (context, updateDialog) => DropdownButtonFormField<int>(
            initialValue: chosenDay,
            decoration: const InputDecoration(labelText: 'Weekly off day'),
            items: List.generate(7, (index) => index + 1)
                .map(
                  (day) => DropdownMenuItem(
                    value: day,
                    child: Text(_weekdayName(day)),
                  ),
                )
                .toList(),
            onChanged: (day) => updateDialog(() => chosenDay = day!),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: _blue),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (changed == true) {
      try {
        await HrmsDashboardApi.saveWeeklyOff(chosenDay);
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Weekly off was not saved: $error')),
        );
        return;
      }
      await CalendarStore.saveWeeklyOff(chosenDay);
      if (!mounted) return;
      setState(() => weeklyOffDay = chosenDay);
    }
  }

  Future<void> _showHistory() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Calendar change history'),
        content: SizedBox(
          width: 420,
          child: overrides.isEmpty
              ? const Text('No calendar overrides have been saved yet.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: overrides.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, index) {
                    final item = overrides.reversed.toList()[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${item['date']} • ${item['status']}'),
                      subtitle: Text('${item['scope']} — ${item['reason']}'),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveOverride() async {
    final reason = reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a reason for this change.')),
      );
      return;
    }
    final item = <String, dynamic>{
      'date': _dateKey(_selectedDate),
      'status': selectedStatus,
      'scope': scope,
      'reason': reason,
      'recalculate': recalculate,
      'notifyEmployees': notifyEmployees,
      'savedAt': DateTime.now().toIso8601String(),
    };
    final updated = [
      ...overrides.where((existing) => existing['date'] != item['date']),
      item,
    ];
    try {
      await HrmsDashboardApi.saveCalendarOverride(item);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Calendar was not saved for employees: $error')),
      );
      return;
    }
    await CalendarStore.saveOverrides(updated);
    if (notifyEmployees) {
      await CalendarStore.addNotification({
        'title': 'Work calendar updated',
        'message': '${item['date']} changed to ${item['status']}',
        'scope': scope,
        'createdAt': DateTime.now().toIso8601String(),
        'read': false,
      });
    }
    if (!mounted) return;
    setState(() => overrides = updated);
    Navigator.pop(context, true);
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(
        Icons.edit_calendar_outlined,
        color: HrmsColors.blue,
        size: 38,
      ),
      const SizedBox(width: 18),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manage Calendar',
              style: TextStyle(
                color: HrmsColors.navy,
                fontSize: 23,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'Set weekly offs and change specific working days',
              style: TextStyle(color: Color(0xFF50649E), fontSize: 13),
            ),
          ],
        ),
      ),
      IconButton(
        onPressed: onClose,
        icon: const Icon(Icons.close_rounded, color: HrmsColors.navy, size: 25),
      ),
    ],
  );
}

class _DefaultWeeklyOff extends StatelessWidget {
  const _DefaultWeeklyOff({required this.day, required this.onEdit});

  final String day;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 14, 18, 14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: HrmsColors.line),
      borderRadius: BorderRadius.circular(9),
      boxShadow: const [
        BoxShadow(
          color: Color(0x08071A72),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Default Weekly Off',
          style: TextStyle(
            color: HrmsColors.navy,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (_, constraints) {
            final compact = constraints.maxWidth < 650;
            final details = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DefaultItem(label: 'Day', value: day),
                _VerticalRule(),
                _DefaultItem(label: 'Status', value: 'OFF', badge: true),
                _VerticalRule(),
                _DefaultItem(label: 'Applies To', value: 'All Employees'),
              ],
            );
            final edit = OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 19),
              label: const Text('Edit Default'),
              style: OutlinedButton.styleFrom(
                foregroundColor: HrmsColors.blue,
                side: const BorderSide(color: HrmsColors.blue),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 12,
                    children: [
                      _DefaultItem(label: 'Day', value: day, compact: true),
                      _DefaultItem(
                        label: 'Status',
                        value: 'OFF',
                        badge: true,
                        compact: true,
                      ),
                      _DefaultItem(
                        label: 'Applies To',
                        value: 'All Employees',
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  edit,
                ],
              );
            }
            return Row(children: [details, const Spacer(), edit]);
          },
        ),
      ],
    ),
  );
}

class _DefaultItem extends StatelessWidget {
  const _DefaultItem({
    required this.label,
    required this.value,
    this.badge = false,
    this.compact = false,
  });
  final String label, value;
  final bool badge;
  final bool compact;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: compact ? 118 : 145,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: HrmsColors.navy, fontSize: 11),
        ),
        const SizedBox(height: 6),
        badge
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8ECF4),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  value,
                  style: const TextStyle(color: HrmsColors.navy, fontSize: 11),
                ),
              )
            : Text(
                value,
                style: const TextStyle(color: HrmsColors.navy, fontSize: 13),
              ),
      ],
    ),
  );
}

class _VerticalRule extends StatelessWidget {
  const _VerticalRule();
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 39,
    margin: const EdgeInsets.only(right: 18),
    color: HrmsColors.line,
  );
}

class _CalendarPanel extends StatelessWidget {
  const _CalendarPanel({
    required this.month,
    required this.selectedDay,
    required this.onPrevious,
    required this.onNext,
    required this.weeklyOffDay,
    required this.statusForDate,
    required this.actualStatusForDate,
    required this.onSelected,
  });

  final DateTime month;
  final int selectedDay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final int weeklyOffDay;
  final String Function(DateTime) statusForDate;
  final String Function(DateTime) actualStatusForDate;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final statusCounts = <String, int>{
      'Working Day': 0,
      'Weekly Off': 0,
      'Holiday': 0,
    };
    for (var day = 1; day <= daysInMonth; day++) {
      final status = actualStatusForDate(
        DateTime(month.year, month.month, day),
      );
      if (statusCounts.containsKey(status)) {
        statusCounts[status] = statusCounts[status]! + 1;
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: HrmsColors.line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _ArrowButton(icon: Icons.chevron_left_rounded, onTap: onPrevious),
              const SizedBox(width: 14),
              Text(
                '${_monthName(month.month)} ${month.year}',
                style: const TextStyle(
                  color: HrmsColors.blue,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              _ArrowButton(icon: Icons.chevron_right_rounded, onTap: onNext),
            ],
          ),
          const Divider(height: 15, color: HrmsColors.line),
          Row(
            children: [
              for (final day in [
                'MON',
                'TUE',
                'WED',
                'THU',
                'FRI',
                'SAT',
                'SUN',
              ])
                Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: const TextStyle(
                        color: HrmsColors.navy,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.04,
            ),
            itemCount: 42,
            itemBuilder: (_, index) {
              final offset = DateTime(month.year, month.month, 1).weekday - 1;
              final day = index - offset + 1;
              if (day < 1 || day > daysInMonth) {
                return const SizedBox.shrink();
              }
              final date = DateTime(month.year, month.month, day);
              return _CalendarDay(
                date: date,
                day: day,
                weeklyOffDay: weeklyOffDay,
                status: statusForDate(date),
                selected: day == selectedDay,
                onTap: () => onSelected(day),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CalendarLegend(
                'Working Day',
                HrmsColors.blue,
                statusCounts['Working Day']!,
              ),
              const SizedBox(width: 18),
              _CalendarLegend(
                'Weekly Off',
                const Color(0xFF63718F),
                statusCounts['Weekly Off']!,
              ),
              const SizedBox(width: 18),
              _CalendarLegend(
                'Holiday',
                const Color(0xFF8500C8),
                statusCounts['Holiday']!,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _monthName(int month) => const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month - 1];
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      width: 30,
      height: 28,
      decoration: BoxDecoration(
        border: Border.all(color: HrmsColors.line),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Icon(icon, color: HrmsColors.blue, size: 20),
    ),
  );
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.day,
    required this.weeklyOffDay,
    required this.status,
    required this.selected,
    required this.onTap,
  });
  final DateTime date;
  final int day;
  final int weeklyOffDay;
  final String status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weeklyOff = status == 'Weekly Off';
    final isAugust2026 = date.year == 2026 && date.month == 8;
    final holiday = status == 'Holiday' || (isAugust2026 && day == 25);
    final override =
        status == 'Override' ||
        (!weeklyOff && !holiday && isAugust2026 && day == 15);
    final color = holiday
        ? _purple
        : override
        ? _green
        : weeklyOff
        ? _off
        : HrmsColors.blue;
    final label = override
        ? 'Override'
        : holiday
        ? 'Holiday'
        : weeklyOff
        ? 'OFF'
        : 'Working Day';
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: weeklyOff ? const Color(0xFFF6F8FC) : Colors.white,
          border: Border.all(
            color: selected ? HrmsColors.blue : const Color(0xFFE4E9F2),
            width: selected ? 1.5 : 1,
          ),
          borderRadius: selected ? BorderRadius.circular(6) : BorderRadius.zero,
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                color: holiday ? _purple : HrmsColors.navy,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: HrmsColors.navy, fontSize: 7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend(this.label, this.color, this.count);
  final String label;
  final Color color;
  final int count;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: HrmsColors.navy, fontSize: 10)),
      const SizedBox(width: 4),
      Text(
        '$count',
        style: const TextStyle(
          color: HrmsColors.navy,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _EditDatePanel extends StatelessWidget {
  const _EditDatePanel({
    required this.selectedDay,
    required this.month,
    required this.status,
    required this.currentStatus,
    required this.scope,
    required this.recalculate,
    required this.notifyEmployees,
    required this.reasonController,
    required this.onStatusChanged,
    required this.onScopeChanged,
    required this.onRecalculateChanged,
    required this.onNotifyChanged,
  });
  final int selectedDay;
  final DateTime month;
  final String status, currentStatus, scope;
  final bool recalculate;
  final bool notifyEmployees;
  final TextEditingController reasonController;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String> onScopeChanged;
  final ValueChanged<bool> onRecalculateChanged;
  final ValueChanged<bool> onNotifyChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: HrmsColors.line),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Edit Selected Date',
          style: TextStyle(
            color: HrmsColors.blue,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _LabelValue(
                label: 'Selected Date',
                value:
                    '${_weekday(month, selectedDay)}, '
                    '$selectedDay ${_shortMonth(month.month)} ${month.year}',
              ),
            ),
            _LabelValue(
              label: 'Current Status',
              value: currentStatus,
              badge: true,
            ),
          ],
        ),
        const SizedBox(height: 13),
        const Text('Change Status', style: _fieldLabel),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: status,
          onChanged: onStatusChanged,
          decoration: _fieldDecoration(
            prefix: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: _green,
                shape: BoxShape.circle,
              ),
            ),
          ),
          items: const ['Working Day', 'Weekly Off', 'Holiday']
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
        ),
        const SizedBox(height: 13),
        const Text('Apply To', style: _fieldLabel),
        const SizedBox(height: 6),
        _ScopeSelector(scope: scope, onChanged: onScopeChanged),
        const SizedBox(height: 13),
        const Text('Reason', style: _fieldLabel),
        const SizedBox(height: 6),
        TextField(
          controller: reasonController,
          maxLines: 2,
          decoration: _fieldDecoration(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Recalculate attendance and payroll',
                style: TextStyle(color: HrmsColors.navy, fontSize: 11),
              ),
            ),
            const Icon(Icons.info_outline, color: Color(0xFF50649E), size: 14),
            const SizedBox(width: 16),
            Switch(
              value: recalculate,
              onChanged: onRecalculateChanged,
              activeThumbColor: HrmsColors.blue,
            ),
          ],
        ),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Notify affected employees',
                style: TextStyle(color: HrmsColors.navy, fontSize: 11),
              ),
            ),
            Switch(
              value: notifyEmployees,
              onChanged: onNotifyChanged,
              activeThumbColor: HrmsColors.blue,
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4FF),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: HrmsColors.blue, size: 19),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This change updates working days, attendance totals and salary calculations.',
                  style: TextStyle(
                    color: HrmsColors.blue,
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static String _weekday(DateTime month, int day) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][DateTime(month.year, month.month, day).weekday - 1];

  static String _shortMonth(int month) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month - 1];
}

class _LabelValue extends StatelessWidget {
  const _LabelValue({
    required this.label,
    required this.value,
    this.badge = false,
  });
  final String label, value;
  final bool badge;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xFF50649E), fontSize: 10),
      ),
      const SizedBox(height: 6),
      badge
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE6EAF3),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(
                value,
                style: const TextStyle(color: HrmsColors.navy, fontSize: 9),
              ),
            )
          : Text(
              value,
              style: const TextStyle(
                color: HrmsColors.navy,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
    ],
  );
}

class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({required this.scope, required this.onChanged});
  final String scope;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 38,
    decoration: BoxDecoration(
      border: Border.all(color: HrmsColors.line),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        for (final item in const [
          ('All Employees', Icons.groups_outlined),
          ('Department', Icons.apartment_outlined),
          ('Selected Employees', Icons.person_outline),
        ])
          Expanded(
            child: InkWell(
              onTap: () => onChanged(item.$1),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scope == item.$1 ? HrmsColors.blue : Colors.white,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.$2,
                      color: scope == item.$1 ? Colors.white : HrmsColors.navy,
                      size: 15,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        item.$1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scope == item.$1
                              ? Colors.white
                              : HrmsColors.navy,
                          fontSize: 8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

InputDecoration _fieldDecoration({Widget? prefix}) => InputDecoration(
  prefixIcon: prefix == null ? null : Center(widthFactor: 1, child: prefix),
  filled: true,
  fillColor: Colors.white,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: HrmsColors.line),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: HrmsColors.blue),
  ),
);

class _DialogFooter extends StatelessWidget {
  const _DialogFooter({
    required this.compact,
    required this.onHistory,
    required this.onCancel,
    required this.onSave,
  });
  final bool compact;
  final VoidCallback onHistory, onCancel, onSave;

  @override
  Widget build(BuildContext context) {
    final history = TextButton.icon(
      onPressed: onHistory,
      icon: const Icon(Icons.calendar_month_outlined, size: 18),
      label: const Text('View change history'),
      style: TextButton.styleFrom(foregroundColor: HrmsColors.blue),
    );
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          onPressed: onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: HrmsColors.blue,
            side: const BorderSide(color: HrmsColors.blue),
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 18),
        FilledButton(
          onPressed: onSave,
          style: FilledButton.styleFrom(
            backgroundColor: HrmsColors.blue,
            padding: const EdgeInsets.symmetric(horizontal: 43, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: const Text('Save Override'),
        ),
      ],
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: history),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: HrmsColors.blue,
                    side: const BorderSide(color: HrmsColors.blue),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: HrmsColors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Save Override'),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return Row(children: [history, const Spacer(), buttons]);
  }
}

const _fieldLabel = TextStyle(
  color: HrmsColors.navy,
  fontSize: 10,
  fontWeight: FontWeight.w600,
);
