import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../shared/theme/admin_surface_palette.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../../../screens/admin_dashboard/helpers/csv_export.dart';
import '../../../screens/login_screen.dart';
import '../../../services/auth_service.dart';
import '../../../services/hrms_dashboard_api.dart';
import '../../shared/widgets/admin_top_nav.dart';
import 'widgets/attendance_grid.dart';
import 'widgets/manage_calendar_dialog.dart';
import 'widgets/manage_time_dialog.dart';

const _navy = Color(0xFF07186F);
const _blue = Color(0xFFE3162A);
const _green = Color(0xFF008A32);
const _red = Color(0xFFE00012);
const _orange = Color(0xFFFF6A00);
const _purple = Color(0xFF7E20E8);
const _line = Color(0xFFD9E2F1);
const _muted = Color(0xFF52638E);
const _a1Red = Color(0xFFE3162A);
const _a1RedDeep = Color(0xFFB70B1B);

String _fullMonthName(String month) =>
    const {
      'Jan': 'January',
      'Feb': 'February',
      'Mar': 'March',
      'Apr': 'April',
      'May': 'May',
      'Jun': 'June',
      'Jul': 'July',
      'Aug': 'August',
      'Sep': 'September',
      'Oct': 'October',
      'Nov': 'November',
      'Dec': 'December',
    }[month] ??
    month;

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.settingsAction, this.inSettingsDialog = false});

  final String? settingsAction;
  final bool inSettingsDialog;

  static Widget builder(BuildContext context) => const DashboardPage();

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _openedSettingsAction = false;
  final ScrollController _tableScrollController = ScrollController();
  bool _monthly = true;
  bool _showSummary = true;
  bool _employeeListExpanded = false;
  late String _month;
  late int _year;
  int _weeklyOffDay = DateTime.sunday;
  List<Map<String, dynamic>> _calendarOverrides = [];
  List<_EmployeeAttendance> _employees = [];
  int _kpiTotal = 0;
  int _kpiPresent = 0;
  int _kpiAbsent = 0;
  int _kpiLate = 0;
  bool _loading = true;
  String? _error;

  static const _monthCodes = [
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
  ];

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _year = today.year;
    _month = _monthCodes[today.month - 1];
    _boot();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final action = widget.settingsAction ??
        (ModalRoute.of(context)?.settings.arguments as Map?)?['settingsAction'];
    if (_openedSettingsAction || action == null) return;
    _openedSettingsAction = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (action == 'manageTime') await _openManageTime();
      if (action == 'manageCalendar') await _openManageCalendar();
      if (widget.inSettingsDialog && mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _boot() async {
    await _loadCalendarSettings();
    await _loadDashboard();
  }

  Future<void> _loadCalendarSettings() async {
    final weeklyOff = await CalendarStore.loadWeeklyOff();
    final overrides = await CalendarStore.loadOverrides();
    if (!mounted) return;
    setState(() {
      _weeklyOffDay = weeklyOff;
      _calendarOverrides = overrides;
    });
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await HrmsDashboardApi.month(
        year: _year,
        month: _monthCodes.indexOf(_month) + 1,
        weeklyOff: _weeklyOffDay,
      );
      final kpis = Map<String, dynamic>.from(data['kpis'] as Map? ?? {});
      final items = (data['employees'] as List? ?? [])
          .whereType<Map>()
          .map(
            (item) =>
                _EmployeeAttendance.fromApi(Map<String, dynamic>.from(item)),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _employees = items;
        _kpiTotal = _asInt(kpis['totalEmployees']);
        _kpiPresent = _asInt(kpis['present']);
        _kpiAbsent = _asInt(kpis['absent']);
        _kpiLate = _asInt(kpis['late']);
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  int _asInt(dynamic value) =>
      value is int ? value : int.tryParse('$value') ?? 0;

  static String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).substring(2)}';

  String _dayMarkColor(String code) {
    switch (code) {
      case 'P':
        return _hex(_green);
      case 'A':
        return _hex(_red);
      case 'L':
        return _hex(_orange);
      case 'HL':
      case 'LV':
        return _hex(_purple);
      default:
        return _hex(_muted); // OFF, –, blank
    }
  }

  Future<void> _exportAttendanceCsv() async {
    final month = _monthCodes.indexOf(_month) + 1;
    final dayCount = DateTime(_year, month + 1, 0).day;
    const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final monthLabel = '${_fullMonthName(_month)} $_year';
    final logoBytes = (await rootBundle.load(
      'assets/images/a1_blowers_logo_header.png',
    )).buffer.asUint8List();
    final logoData = base64Encode(logoBytes);

    final html = StringBuffer();
    html.writeln('''
      <html>
      <head>
      <meta charset="utf-8">
      <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 18px; color: ${_hex(_navy)}; }
        .brand { border-bottom: 2px solid #0767F2; padding-bottom: 12px; margin-bottom: 10px; }
        .brand img { width: 110px; height: auto; vertical-align: middle; margin-right: 16px; }
        .brand-title { display: inline-block; vertical-align: middle; font-size: 18px; font-weight: bold; color: ${_hex(_navy)}; }
        .brand-subtitle { display: block; font-size: 11px; font-weight: normal; color: ${_hex(_muted)}; margin-top: 3px; }
        .title { font-size: 16px; font-weight: bold; color: ${_hex(_navy)}; padding: 8px 4px; }
        .legend td { font-size: 10px; font-weight: bold; padding: 4px 8px; color: ${_hex(_navy)}; }
        table.data { border-collapse: collapse; margin-top: 6px; }
        table.data th { background-color: #EAF1FF; font-size: 10px; font-weight: 700; padding: 7px 6px; border: 1px solid ${_hex(_line)}; color: ${_hex(_navy)}; text-align: center; white-space: nowrap; }
        table.data td { font-size: 10px; padding: 7px 6px; border: 1px solid ${_hex(_line)}; text-align: center; color: ${_hex(_navy)}; }
        td.name { text-align: left; font-weight: 700; }
        td.designation { text-align: left; color: ${_hex(_muted)}; font-weight: 400; }
      </style>
      </head>
      <body>
      <table class="brand"><tr><td><img src="data:image/png;base64,$logoData"><span class="brand-title">A1 BLOWERS<span class="brand-subtitle">Employee Attendance Directory</span></span></td><td style="text-align:right; color:${_hex(_muted)}; font-size:10px;">Generated ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}</td></tr></table>
      <table>
        <tr><td class="title">$monthLabel Attendance</td></tr>
      </table>
      <table class="legend">
        <tr>
          <td style="color:${_hex(_green)}">● Present</td>
          <td style="color:${_hex(_red)}">● Absent</td>
          <td style="color:${_hex(_orange)}">● Late</td>
          <td style="color:${_hex(_purple)}">● Holiday</td>
          <td style="color:${_hex(_purple)}">● Leave</td>
          <td style="color:${_hex(_purple)}">● Half Leave</td>
          <td style="color:${_hex(_muted)}">○ Weekly Off</td>
        </tr>
      </table>
      <table class="data">
        <tr>
          <th>Employee Name</th>
          <th>Designation</th>
    ''');
    for (var day = 1; day <= dayCount; day++) {
      html.write(
        '<th>$day<br>${weekdayNames[DateTime(_year, month, day).weekday - 1]}</th>',
      );
    }
    html.writeln('''
          <th style="color:${_hex(_green)}">Present</th>
          <th style="color:${_hex(_orange)}">Late</th>
          <th style="color:${_hex(_purple)}">Leave</th>
          <th style="color:${_hex(_purple)}">Half Leave</th>
          <th style="color:${_hex(_blue)}">Earned Leave</th>
          <th>Salary Per Month</th>
          <th style="color:${_hex(_red)}">Absent Deduction</th>
          <th>Updated Salary</th>
        </tr>
    ''');

    for (final employee in _employees) {
      html.write(
        '<tr><td class="name">${employee.name}</td>'
        '<td class="designation">${employee.designation}</td>',
      );
      for (var i = 0; i < dayCount; i++) {
        final mark = i < employee.days.length ? employee.days[i] : '';
        final display = mark.isEmpty ? '–' : (mark == 'LV' ? 'L' : mark);
        html.write('<td style="color:${_dayMarkColor(mark)}">$display</td>');
      }
      html.writeln('''
          <td style="color:${_hex(_green)}; font-weight:700;">${employee.present}</td>
          <td style="color:${_hex(_orange)}; font-weight:700;">${employee.late}</td>
          <td style="color:${_hex(_purple)}; font-weight:700;">${employee.approvedLeave}</td>
          <td style="color:${_hex(_purple)}; font-weight:700;">${employee.halfLeave}</td>
          <td style="color:${_hex(_blue)}; font-weight:700;">${employee.earnedLeave}</td>
          <td>${employee.salary}</td>
          <td style="color:${_hex(_red)}; font-weight:700;">${employee.absent} ${employee.absentDeduction}</td>
          <td>${employee.updatedSalary}</td>
        </tr>
      ''');
    }

    html.writeln('</table></body></html>');

    final fileName =
        'A1_Blowers_Attendance_$_month${_year}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xls';
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(html.toString())];
    await saveAndShareCsv(bytes, fileName);
  }

  Future<void> _openManageTime() async {
    await showManageTimeDialog(context);
  }

  Future<void> _openManageCalendar() async {
    final saved = await showManageCalendarDialog(context);
    if (saved) {
      await _loadCalendarSettings();
      await _loadDashboard();
    }
  }

  @override
  void dispose() {
    _tableScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) {
      return _MobileDashboard(
        monthly: _monthly,
        onMonthlyChanged: (value) => setState(() => _monthly = value),
        year: _year,
        onYearChanged: (value) {
          setState(() => _year = value);
          _loadDashboard();
        },
        onExport: _exportAttendanceCsv,
        month: _month,
        employees: _employees,
        total: _kpiTotal,
        present: _kpiPresent,
        absent: _kpiAbsent,
        late: _kpiLate,
        loading: _loading,
        error: _error,
        onRetry: _loadDashboard,
      );
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          const AdminTopNav(activeRoute: '/admin/dashboard'),
          Expanded(
            child: _employeeListExpanded
                ? SingleChildScrollView(
                    child: Padding(
                      padding: _dashboardPadding(width),
                      child: _dashboardContent(expanded: true),
                    ),
                  )
                : Padding(
                    padding: _dashboardPadding(width),
                    child: _dashboardContent(expanded: false),
                  ),
          ),
        ],
      ),
    );
  }

  EdgeInsets _dashboardPadding(double width) => EdgeInsets.fromLTRB(
    width < 1100 ? 16 : 20,
    14,
    width < 1100 ? 16 : 20,
    12,
  );

  Widget _dashboardContent({required bool expanded}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: expanded ? MainAxisSize.min : MainAxisSize.max,
    children: [
      SizedBox(
        height: 104,
        child: _KpiRow(
          monthly: _monthly,
          total: _kpiTotal,
          monthlyWorkingDays: _monthlyWorkingDays,
          present: _kpiPresent,
          absent: _kpiAbsent,
          late: _kpiLate,
        ),
      ),
      const SizedBox(height: 12),
      _QuickActionBar(
        onManageTime: _openManageTime,
        onManageCalendar: _openManageCalendar,
      ),
      const SizedBox(height: 12),
      if (expanded)
        _attendancePanel(expanded: true)
      else
        Expanded(child: _attendancePanel(expanded: false)),
      if (_monthly) ...[
        const SizedBox(height: 10),
        SizedBox(height: 40, child: _monthSelector()),
      ],
    ],
  );

  int get _monthlyWorkingDays {
    final monthNumber = _monthCodes.indexOf(_month) + 1;
    final days = DateTime(_year, monthNumber + 1, 0).day;
    var count = 0;
    for (var day = 1; day <= days; day++) {
      if (DateTime(_year, monthNumber, day).weekday != _weeklyOffDay) count++;
    }
    return count;
  }

  Widget _attendancePanel({required bool expanded}) {
    final palette = AdminSurfacePalette.of(context);
    return Container(
    decoration: BoxDecoration(
      color: palette.surface,
      border: Border.all(color: palette.border),
      borderRadius: BorderRadius.circular(14),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        SizedBox(
          height: 60,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE8EB),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.calendar_month_outlined,
                    color: _a1Red,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _monthly
                      ? '${_monthName(_month)} $_year Attendance'
                      : '$_year Yearly Attendance',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 18),
                const _AttendanceLegend(),
                const SizedBox(width: 18),
                if (_monthly) ...[
                  Tooltip(
                    message: _showSummary
                        ? 'Hide payroll summary columns'
                        : 'Show payroll summary columns',
                    child: OutlinedButton(
                      onPressed: () =>
                          setState(() => _showSummary = !_showSummary),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _showSummary ? _a1Red : _muted,
                        backgroundColor: _showSummary
                            ? const Color(0xFFFFE8EB)
                            : palette.surface,
                        side: BorderSide(
                          color: _showSummary
                              ? _a1Red
                              : const Color(0xFFBFD2F2),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Icon(
                        _showSummary
                            ? Icons.view_column
                            : Icons.view_column_outlined,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  onPressed: _exportAttendanceCsv,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.text,
                    side: BorderSide(color: palette.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  icon: const Icon(Icons.file_download_outlined, size: 20),
                  label: const Text(
                    'Export',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: _line),
        if (expanded)
          _attendanceContent(expanded: true)
        else
          Expanded(child: _attendanceContent(expanded: false)),
      ],
    ),
  );
  }

  Widget _attendanceContent({required bool expanded}) => _loading
      ? const Center(child: CircularProgressIndicator())
      : _error != null
      ? Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
              FilledButton(
                onPressed: _loadDashboard,
                child: const Text('Retry'),
              ),
            ],
          ),
        )
      : _monthly
      ? _AttendanceTable(
          horizontalController: _tableScrollController,
          year: _year,
          month: _monthCodes.indexOf(_month) + 1,
          weeklyOffDay: _weeklyOffDay,
          overrides: _calendarOverrides,
          employees: _employees,
          showSummary: _showSummary,
          expanded: expanded,
          onToggleExpanded: () =>
              setState(() => _employeeListExpanded = !_employeeListExpanded),
        )
      : _YearlyAttendanceSummary(employees: _employees);

  Widget _monthSelector() {
    const months = _monthCodes;
    final palette = AdminSurfacePalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (final month in months)
            Expanded(
              child: InkWell(
                onTap: () {
                  setState(() => _month = month);
                  _loadDashboard();
                },
                child: Container(
                  height: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: month == _month ? _a1Red : palette.surface,
                    border: Border(left: BorderSide(color: palette.border)),
                    borderRadius: month == _month
                        ? BorderRadius.circular(7)
                        : BorderRadius.zero,
                  ),
                  child: Text(
                    '$month $_year',
                    style: TextStyle(
                      color: month == _month ? Colors.white : palette.text,
                      fontSize: 12,
                      fontWeight: month == _month
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _monthName(String month) => const {
    'Jan': 'January',
    'Feb': 'February',
    'Mar': 'March',
    'Apr': 'April',
    'May': 'May',
    'Jun': 'June',
    'Jul': 'July',
    'Aug': 'August',
    'Sep': 'September',
    'Oct': 'October',
    'Nov': 'November',
    'Dec': 'December',
  }[month]!;
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.monthly,
    required this.monthlyWorkingDays,
    required this.total,
    required this.present,
    required this.absent,
    required this.late,
  });

  final bool monthly;
  final int monthlyWorkingDays;
  final int total, present, absent, late;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _KpiCard(
          label: 'Monthly Working Days',
          value: '$monthlyWorkingDays',
          subtitle: 'Configured workdays',
          color: const Color(0xFF5B4BC4),
          icon: Icons.calendar_month_outlined,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _KpiCard(
          label: 'Total Employees',
          value: '$total',
          subtitle: 'Active workforce',
          color: const Color(0xFF17335F),
          icon: Icons.groups_2_outlined,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _KpiCard(
          label: 'Present Today',
          value: '$present',
          subtitle: total == 0
              ? 'No employees yet'
              : '${((present / total) * 100).round()}% of total',
          color: _green,
          icon: Icons.check_rounded,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _KpiCard(
          label: 'Attendance Exceptions',
          value: '${absent + late}',
          subtitle: '$late late · $absent absent',
          color: _orange,
          icon: Icons.warning_amber_rounded,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _KpiCard(
          label: 'Pending Approvals',
          value: '$absent',
          subtitle: 'Leave · devices · overtime',
          color: _a1Red,
          icon: Icons.assignment_outlined,
        ),
      ),
    ],
  );
}

class _QuickActionBar extends StatelessWidget {
  const _QuickActionBar({
    required this.onManageTime,
    required this.onManageCalendar,
  });

  final VoidCallback onManageTime;
  final VoidCallback onManageCalendar;

  @override
  Widget build(BuildContext context) => Container(
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [_a1Red, _a1RedDeep],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      borderRadius: BorderRadius.circular(13),
      boxShadow: const [
        BoxShadow(
          color: Color(0x2EE3162A),
          blurRadius: 20,
          offset: Offset(0, 9),
        ),
      ],
    ),
    child: Row(
      children: [
        const Icon(Icons.bolt_rounded, color: Colors.white, size: 24),
        const SizedBox(width: 9),
        const Text(
          'Quick Actions',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 16),
        Container(width: 1, height: 28, color: const Color(0x80FFFFFF)),
        const SizedBox(width: 16),
        Expanded(
          child: _QuickActionButton(
            label: 'Manage Time',
            icon: Icons.schedule_outlined,
            onTap: onManageTime,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            label: 'Manage Calendar',
            icon: Icons.calendar_month_outlined,
            onTap: onManageCalendar,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            label: 'Approve Leave',
            icon: Icons.flight_takeoff_outlined,
            onTap: () =>
                Navigator.pushReplacementNamed(context, '/admin/approvals'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            label: 'Approve Devices',
            icon: Icons.phone_android_outlined,
            onTap: () =>
                Navigator.pushReplacementNamed(context, '/admin/approvals'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            label: 'Approve Extra Hours',
            icon: Icons.groups_2_outlined,
            onTap: () =>
                Navigator.pushReplacementNamed(context, '/admin/approvals'),
          ),
        ),
      ],
    ),
  );
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0x1FFFFFFF),
    borderRadius: BorderRadius.circular(9),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AttendanceTable extends StatelessWidget {
  const _AttendanceTable({
    required this.horizontalController,
    required this.year,
    required this.month,
    required this.weeklyOffDay,
    required this.overrides,
    required this.employees,
    required this.showSummary,
    required this.expanded,
    required this.onToggleExpanded,
  });

  final ScrollController horizontalController;
  final int year;
  final int month;
  final int weeklyOffDay;
  final List<Map<String, dynamic>> overrides;
  final List<_EmployeeAttendance> employees;
  final bool showSummary;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      DateTime(year, month + 1, 0).day,
      (index) => index + 1,
    );
    const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (employees.isEmpty) {
      return const Center(child: Text('No employees to show.'));
    }
    return AttendanceGrid(
      showSummary: showSummary,
      expanded: expanded,
      onToggleExpanded: onToggleExpanded,
      days: days,
      dayLabels: [
        for (final day in days)
          weekdayNames[DateTime(year, month, day).weekday - 1],
      ],
      rows: [
        for (final employee in employees)
          AttendanceRowData(
            name: employee.name,
            designation: employee.designation,
            days: [
              for (var i = 0; i < days.length; i++)
                AttendanceDayMark(
                  _markForDay(
                    i,
                    employee,
                    year,
                    month,
                    weeklyOffDay,
                    overrides,
                  ),
                ),
            ],
            present: employee.present,
            absent: employee.absent,
            absentDeduction: employee.absentDeduction,
            late: employee.late,
            excused: employee.excused,
            unexcused: employee.unexcused,
            halfLeave: employee.halfLeave,
            earnedLeave: employee.earnedLeave,
            approvedLeave: employee.approvedLeave,
            salaryPerMonth: employee.salary,
            totalSalaryAfterLeaves:
                '${employee.daysPaid} ${employee.afterLeaves}',
            updatedSalary: employee.updatedSalary,
          ),
      ],
    );
  }

  String _markForDay(
    int index,
    _EmployeeAttendance employee,
    int year,
    int month,
    int weeklyOffDay,
    List<Map<String, dynamic>> overrides,
  ) {
    final day = index + 1;
    final dateKey =
        '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    final changes = overrides.where((item) => item['date'] == dateKey).toList();
    if (changes.isNotEmpty) {
      final status = changes.last['status'] as String;
      if (status == 'Weekly Off') return 'OFF';
      if (status == 'Holiday') return 'H';
    }
    if (index < employee.days.length) return employee.days[index];
    if (DateTime(year, month, day).weekday == weeklyOffDay) return 'OFF';
    return '';
  }
}

class _YearlyAttendanceSummary extends StatelessWidget {
  const _YearlyAttendanceSummary({required this.employees});
  final List<_EmployeeAttendance> employees;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const headerHeight = 52.0;
      if (employees.isEmpty) {
        return const Center(child: Text('No employees to show.'));
      }
      return SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(constraints.maxWidth, 1050),
            child: Column(
              children: [
                const SizedBox(height: headerHeight, child: _YearlyHeaderRow()),
                for (final employee in employees)
                  SizedBox(
                    height: 42,
                    child: _YearlyEmployeeRow(employee: employee),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _EmployeeAttendance {
  const _EmployeeAttendance({
    required this.name,
    required this.designation,
    required this.present,
    required this.absent,
    required this.absentDeduction,
    required this.late,
    required this.halfLeave,
    required this.earnedLeave,
    required this.approvedLeave,
    required this.excused,
    required this.unexcused,
    required this.salary,
    required this.daysPaid,
    required this.afterLeaves,
    required this.updatedSalary,
    required this.days,
  });

  final String name;
  final String designation;
  final int present;
  final int absent;
  final String absentDeduction;
  final int late;
  final int halfLeave;
  final int earnedLeave;
  final int approvedLeave;
  final int excused;
  final int unexcused;
  final String salary;
  final String daysPaid;
  final String afterLeaves;
  final String updatedSalary;
  final List<String> days;

  factory _EmployeeAttendance.fromApi(Map<String, dynamic> json) {
    int asInt(dynamic value) =>
        value is int ? value : int.tryParse('$value') ?? 0;
    return _EmployeeAttendance(
      name: (json['name'] ?? '').toString(),
      designation: (json['designation'] ?? '').toString(),
      present: asInt(json['present']),
      absent: asInt(json['absent']),
      absentDeduction: (json['absentDeduction'] ?? '–').toString(),
      late: asInt(json['late']),
      halfLeave: asInt(json['halfLeave']),
      earnedLeave: asInt(json['earnedLeave']),
      approvedLeave: asInt(json['approvedLeave']),
      excused: asInt(json['excused']),
      unexcused: asInt(json['unexcused']),
      salary: (json['salary'] ?? 'Not Set').toString(),
      daysPaid: (json['daysPaid'] ?? '0').toString(),
      afterLeaves: (json['afterLeaves'] ?? '–').toString(),
      updatedSalary: (json['updatedSalary'] ?? 'Not Set').toString(),
      days: (json['days'] as List? ?? [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

class _MobileDashboard extends StatelessWidget {
  const _MobileDashboard({
    required this.monthly,
    required this.onMonthlyChanged,
    required this.year,
    required this.onYearChanged,
    required this.onExport,
    required this.month,
    required this.employees,
    required this.total,
    required this.present,
    required this.absent,
    required this.late,
    required this.loading,
    required this.error,
    required this.onRetry,
  });
  final bool monthly;
  final ValueChanged<bool> onMonthlyChanged;
  final int year;
  final ValueChanged<int> onYearChanged;
  final VoidCallback onExport;
  final String month;
  final List<_EmployeeAttendance> employees;
  final int total, present, absent, late;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8FAFF),
    bottomNavigationBar: const AdminMobileBottomNav(
      activeRoute: '/admin/dashboard',
    ),
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      title: Image.asset('assets/images/a1_blowers_logo_header.png', height: 38),
      actions: [
        const Icon(Icons.notifications_none_rounded, color: _navy),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'Workspace',
          onSelected: (value) async {
            if (value == 'workspace') {
              Navigator.of(
                context,
                rootNavigator: true,
              ).pushNamedAndRemoveUntil('/home', (route) => false);
            } else {
              await context.read<AuthService>().logout();
              if (!context.mounted) return;
              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            }
          },
          icon: const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFFEAF0FA),
            child: Icon(Icons.grid_view_rounded, color: _navy, size: 20),
          ),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'workspace',
              child: ListTile(
                leading: Icon(Icons.grid_view_rounded),
                title: Text('Workspace'),
              ),
            ),
            PopupMenuItem(
              value: 'logout',
              child: ListTile(
                leading: Icon(Icons.logout_rounded, color: _red),
                title: Text('Logout', style: TextStyle(color: _red)),
              ),
            ),
          ],
        ),
        const SizedBox(width: 6),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(error!, textAlign: TextAlign.center),
                ),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Admin Dashboard',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Employee attendance and payroll overview',
                  style: TextStyle(color: _muted),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _PeriodToggle(
                        width: null,
                        monthly: monthly,
                        onChanged: onMonthlyChanged,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _YearSelector(
                        compact: true,
                        value: year,
                        onChanged: onYearChanged,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _MobileDashboardMetric(
                      label: 'Employees',
                      value: '$total',
                      color: _blue,
                    ),
                    SizedBox(width: 8),
                    _MobileDashboardMetric(
                      label: 'Present',
                      value: '$present',
                      color: _green,
                    ),
                    SizedBox(width: 8),
                    _MobileDashboardMetric(
                      label: 'Late',
                      value: '$late',
                      color: _orange,
                    ),
                    SizedBox(width: 8),
                    _MobileDashboardMetric(
                      label: 'Absent',
                      value: '$absent',
                      color: _red,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _MobileAttendanceRecords(
                  monthly: monthly,
                  month: month,
                  year: year,
                  employees: employees,
                  onExport: onExport,
                ),
              ],
            ),
          ),
  );
}

class _MobileDashboardMetric extends StatelessWidget {
  const _MobileDashboardMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 80,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MobileAdminDrawer extends StatelessWidget {
  const _MobileAdminDrawer({required this.onManageCalendar});

  final VoidCallback onManageCalendar;

  static const _routes = <(String, IconData, String)>[
    ('Dashboard', Icons.dashboard_outlined, '/admin/dashboard'),
    ('Employees', Icons.groups_outlined, '/admin/employees'),
    ('Clock Logs', Icons.history_rounded, '/admin/clock-logs'),
    ('Approvals', Icons.task_alt_rounded, '/admin/approvals'),
    ('Payroll', Icons.account_balance_wallet_outlined, '/admin/payroll'),
    ('Tracking', Icons.location_on_outlined, '/admin/tracking'),
  ];

  void _open(BuildContext context, String route) {
    Navigator.pop(context);
    Navigator.pushReplacementNamed(context, route);
  }

  Future<void> _logout(BuildContext context) async {
    final auth = context.read<AuthService>();
    Navigator.pop(context);
    await auth.logout();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) => Drawer(
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
            child: Row(
              children: [
                Expanded(
                  child: Image.asset(
                    'assets/images/a1_blowers_logo_header.png',
                    height: 40,
                    alignment: Alignment.centerLeft,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          Expanded(
            child: ListView(
              children: [
                for (final item in _routes)
                  ListTile(
                    leading: Icon(item.$2, color: _navy),
                    title: Text(
                      item.$1,
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => _open(context, item.$3),
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.calendar_month_outlined,
                    color: _navy,
                  ),
                  title: const Text(
                    'Calendar',
                    style: TextStyle(color: _navy, fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onManageCalendar();
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.person_outline_rounded,
                    color: _navy,
                  ),
                  title: const Text(
                    'Profile',
                    style: TextStyle(color: _navy, fontWeight: FontWeight.w600),
                  ),
                  onTap: () => _open(context, '/admin/settings'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: _red),
            title: const Text(
              'Logout',
              style: TextStyle(color: _red, fontWeight: FontWeight.w700),
            ),
            onTap: () => _logout(context),
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

class _MobileAttendanceRecords extends StatelessWidget {
  const _MobileAttendanceRecords({
    required this.monthly,
    required this.month,
    required this.year,
    required this.employees,
    required this.onExport,
  });

  final bool monthly;
  final String month;
  final int year;
  final List<_EmployeeAttendance> employees;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFBFD2F2)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.calendar_month_outlined, color: _blue, size: 22),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                monthly
                    ? '${_fullMonthName(month)} $year Attendance'
                    : '$year Yearly Attendance',
                style: const TextStyle(
                  color: _navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: onExport,
              icon: const Icon(Icons.file_download_outlined, color: _navy),
              tooltip: 'Export',
            ),
          ],
        ),
        const SizedBox(height: 8),
        const _MobileLegend(),
        const SizedBox(height: 8),
        if (employees.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: Text('No attendance records found.')),
          )
        else if (monthly)
          _MobileCalendarScroll(month: month, year: year, employees: employees)
        else
          _MobileYearlySummary(employees: employees),
      ],
    ),
  );
}

class _MobileYearlySummary extends StatelessWidget {
  const _MobileYearlySummary({required this.employees});
  final List<_EmployeeAttendance> employees;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 220,
    child: SingleChildScrollView(
      child: Column(
        children: [
          Container(
            height: 38,
            color: const Color(0xFFF6F8FC),
            child: const Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Text(
                      'Employee',
                      style: TextStyle(
                        color: _navy,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'P',
                      style: TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'L',
                      style: TextStyle(
                        color: _orange,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Leave',
                      style: TextStyle(
                        color: _purple,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Half\nLv',
                      style: TextStyle(
                        color: _purple,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Earn\nLv',
                      style: TextStyle(
                        color: _blue,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text(
                      'Salary',
                      style: TextStyle(
                        color: _navy,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final employee in employees)
            Container(
              height: 42,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Text(
                        employee.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${employee.present}',
                        style: const TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${employee.late}',
                        style: const TextStyle(
                          color: _orange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${employee.approvedLeave}',
                        style: const TextStyle(
                          color: _purple,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${employee.halfLeave}',
                        style: const TextStyle(
                          color: _purple,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${employee.earnedLeave}',
                        style: const TextStyle(
                          color: _blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(
                        employee.updatedSalary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _MobileCalendarScroll extends StatelessWidget {
  const _MobileCalendarScroll({
    required this.month,
    required this.year,
    required this.employees,
  });

  final String month;
  final int year;
  final List<_EmployeeAttendance> employees;

  @override
  Widget build(BuildContext context) {
    const codes = [
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
    ];
    final monthNumber = codes.indexOf(month) + 1;
    final dayCount = DateTime(year, monthNumber + 1, 0).day;
    const employeeWidth = 142.0;
    const dayWidth = 38.0;
    const summaryWidths = [46.0, 40.0, 56.0, 48.0, 52.0, 82.0, 82.0, 82.0];
    const summaryLabels = [
      'Present',
      'Late',
      'Leave',
      'Half\nLeave',
      'Earned\nLeave',
      'Salary\nper month',
      'Absent\ndeduction',
      'Updated\nsalary',
    ];
    final weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final tableWidth =
        employeeWidth +
        dayCount * dayWidth +
        summaryWidths.reduce((a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 7),
          child: Text(
            'Swipe sideways to view all days',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 220,
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    children: [
                      Container(
                        height: 48,
                        color: const Color(0xFFF6F8FC),
                        child: Row(
                          children: [
                            _headerCell('Employee', employeeWidth, left: true),
                            for (var day = 1; day <= dayCount; day++)
                              _headerCell(
                                '$day\n${weekday[DateTime(year, monthNumber, day).weekday - 1].substring(0, 1)}',
                                dayWidth,
                              ),
                            for (
                              var index = 0;
                              index < summaryLabels.length;
                              index++
                            )
                              _headerCell(
                                summaryLabels[index],
                                summaryWidths[index],
                              ),
                          ],
                        ),
                      ),
                      for (final employee in employees)
                        SizedBox(
                          height: 38,
                          child: Row(
                            children: [
                              SizedBox(
                                width: employeeWidth,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 10),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      employee.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _navy,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              for (var index = 0; index < dayCount; index++)
                                SizedBox(
                                  width: dayWidth,
                                  child: Center(
                                    child: _CalendarMark(
                                      value: index < employee.days.length
                                          ? employee.days[index]
                                          : '',
                                    ),
                                  ),
                                ),
                              _summaryCell(
                                '${employee.present}',
                                _green,
                                summaryWidths[0],
                              ),
                              _summaryCell(
                                '${employee.late}',
                                _orange,
                                summaryWidths[1],
                              ),
                              _summaryCell(
                                '${employee.approvedLeave}',
                                _purple,
                                summaryWidths[2],
                              ),
                              _summaryCell(
                                '${employee.halfLeave}',
                                _purple,
                                summaryWidths[3],
                              ),
                              _summaryCell(
                                '${employee.earnedLeave}',
                                _blue,
                                summaryWidths[4],
                              ),
                              _summaryCell(
                                employee.salary,
                                _navy,
                                summaryWidths[5],
                              ),
                              _summaryCell(
                                employee.afterLeaves,
                                _navy,
                                summaryWidths[6],
                              ),
                              _summaryCell(
                                employee.updatedSalary,
                                _navy,
                                summaryWidths[7],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerCell(String label, double width, {bool left = false}) =>
      SizedBox(
        width: width,
        child: Padding(
          padding: EdgeInsets.only(left: left ? 10 : 2),
          child: Align(
            alignment: left ? Alignment.centerLeft : Alignment.center,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _navy,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );

  Widget _summaryCell(String value, Color color, double width) => SizedBox(
    width: width,
    child: Center(
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _CalendarMark extends StatelessWidget {
  const _CalendarMark({required this.value});
  final String value;

  Color get _color {
    final mark = value.toUpperCase();
    if (mark == 'P') return _green;
    if (mark == 'L') return _orange;
    if (mark == 'A') return _red;
    if (mark == 'H' || mark.contains('LEAVE')) return _purple;
    return const Color(0xFF9BA8BC);
  }

  @override
  Widget build(BuildContext context) => Text(
    value.isEmpty ? '–' : value,
    style: TextStyle(color: _color, fontSize: 10, fontWeight: FontWeight.w700),
  );
}

class _MobileLegend extends StatelessWidget {
  const _MobileLegend();
  @override
  Widget build(BuildContext context) => const Wrap(
    spacing: 10,
    runSpacing: 6,
    children: [
      _LegendDot(label: 'Present', color: _green),
      _LegendDot(label: 'Absent', color: _red),
      _LegendDot(label: 'Late', color: _orange),
      _LegendDot(label: 'Leave', color: _purple),
    ],
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
    ],
  );
}

class _MobileEmployeeRecord extends StatelessWidget {
  const _MobileEmployeeRecord({required this.employee});
  final _EmployeeAttendance employee;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFFEAF0FA),
          child: Text(
            employee.name.isEmpty ? '?' : employee.name[0].toUpperCase(),
            style: const TextStyle(color: _navy, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                employee.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                employee.designation,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        _RecordCount(
          label: 'P',
          value: employee.present.toString(),
          color: _green,
        ),
        const SizedBox(width: 10),
        _RecordCount(
          label: 'L',
          value: employee.late.toString(),
          color: _orange,
        ),
      ],
    ),
  );
}

class _RecordCount extends StatelessWidget {
  const _RecordCount({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
      Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
    ],
  );
}

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({
    required this.monthly,
    required this.onChanged,
    this.width = 224,
  });

  final bool monthly;
  final ValueChanged<bool> onChanged;
  final double? width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 48,
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFC9D9F3)),
      borderRadius: BorderRadius.circular(8),
    ),
    clipBehavior: Clip.antiAlias,
    child: Row(
      children: [
        _PeriodButton(
          label: 'Monthly',
          active: monthly,
          onTap: () => onChanged(true),
        ),
        _PeriodButton(
          label: 'Yearly',
          active: !monthly,
          onTap: () => onChanged(false),
        ),
      ],
    ),
  );
}

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Container(
        height: double.infinity,
        alignment: Alignment.center,
        color: active ? _blue : Colors.white,
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : _navy,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

class _YearSelector extends StatelessWidget {
  const _YearSelector({
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFC9D9F3)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.calendar_month_outlined,
          color: _blue,
          size: compact ? 20 : 23,
        ),
        SizedBox(width: compact ? 6 : 14),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: value,
            borderRadius: BorderRadius.circular(10),
            icon: Padding(
              padding: EdgeInsets.only(left: compact ? 4 : 14),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _navy,
                size: 20,
              ),
            ),
            style: TextStyle(
              color: _navy,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 13 : 14,
            ),
            items: List.generate(7, (index) => DateTime.now().year - 3 + index)
                .map(
                  (year) =>
                      DropdownMenuItem<int>(value: year, child: Text('$year')),
                )
                .toList(),
            onChanged: (year) {
              if (year != null) onChanged(year);
            },
          ),
        ),
      ],
    ),
  );
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    this.subtitle = 'Today',
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 245;
      final iconSize = compact ? 38.0 : 46.0;
      return Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE0E6EF)),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x080C1B33),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: compact ? 21 : 26),
            ),
            SizedBox(width: compact ? 10 : 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _muted,
                      fontSize: compact ? 10 : 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: _navy,
                      fontSize: compact ? 19 : 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _muted, fontSize: compact ? 9 : 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _AttendanceLegend extends StatelessWidget {
  const _AttendanceLegend();

  static const items = <(String, String, Color)>[
    ('P', 'Present', _green),
    ('A', 'Absent', Color(0xFFB0000B)),
    ('L', 'Late', _orange),
    ('H', 'Holiday', _purple),
    ('L', 'Leave', _purple),
    ('HL', 'Half Leave', _purple),
    ('OFF', 'Weekly Off (Sunday)', Color(0xFF8C9AB8)),
  ];

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final item in items) ...[
        Container(
          width: item.$1.length > 2 ? 25 : 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: item.$3.withValues(alpha: item.$1 == 'OFF' ? .18 : 1),
            shape: item.$1 == 'OFF' ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: item.$1 == 'OFF' ? BorderRadius.circular(10) : null,
          ),
          child: Text(
            item.$1,
            style: TextStyle(
              color: item.$1 == 'OFF' ? _navy : Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(item.$2, style: const TextStyle(color: _navy, fontSize: 11)),
        const SizedBox(width: 20),
      ],
    ],
  );
}

class _YearlyHeaderRow extends StatelessWidget {
  const _YearlyHeaderRow();

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Color(0xFFFBFCFE),
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: const Row(
      children: [
        _YearHeaderCell('Employee Name', flex: 22),
        _YearHeaderCell('Designation', flex: 20),
        _YearHeaderCell('Present', flex: 11, color: _green),
        _YearHeaderCell('Absent', flex: 11, color: _red),
        _YearHeaderCell('Late', flex: 11, color: _orange),
        _YearHeaderCell('Leave', flex: 11, color: _purple),
        _YearHeaderCell('Half Leave', flex: 11, color: _purple),
        _YearHeaderCell('Earned Leave', flex: 11, color: _blue),
        _YearHeaderCell('Annual Salary', flex: 14),
      ],
    ),
  );
}

class _YearlyEmployeeRow extends StatelessWidget {
  const _YearlyEmployeeRow({required this.employee});

  final _EmployeeAttendance employee;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: Row(
      children: [
        _YearBodyCell(
          flex: 22,
          alignment: Alignment.centerLeft,
          child: Text(
            employee.name,
            style: const TextStyle(
              color: _navy,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _YearBodyCell(
          flex: 20,
          alignment: Alignment.centerLeft,
          child: Text(
            employee.designation,
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
        ),
        _YearStatCell('${employee.present}', _green, 11),
        _YearStatCell('${employee.absent}', _red, 11),
        _YearStatCell('${employee.late}', _orange, 11),
        _YearStatCell('${employee.approvedLeave}', _purple, 11),
        _YearStatCell('${employee.halfLeave}', _purple, 11),
        _YearStatCell('${employee.earnedLeave}', _blue, 11),
        _YearBodyCell(
          flex: 14,
          child: Text(
            _annualSalary(employee.salary),
            style: const TextStyle(
              color: _navy,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );

  static String _annualSalary(String salary) {
    final amount = int.tryParse(salary.replaceAll(RegExp(r'[^0-9]'), ''));
    if (amount == null) return '–';
    final text = (amount * 12).toString();
    // Always use international 3-digit grouping (for example ₹2,000,000),
    // never the Indian lakh/crore grouping (₹20,00,000).
    final formatted = text.replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+$)'),
      (_) => ',',
    );
    return '₹$formatted';
  }
}

class _YearHeaderCell extends StatelessWidget {
  const _YearHeaderCell(this.text, {required this.flex, this.color = _navy});

  final String text;
  final int flex;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _YearBodyCell extends StatelessWidget {
  const _YearBodyCell({
    required this.flex,
    required this.child,
    this.alignment = Alignment.center,
  });

  final int flex;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Container(
      height: double.infinity,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: _line)),
      ),
      child: child,
    ),
  );
}

class _YearStatCell extends StatelessWidget {
  const _YearStatCell(this.value, this.color, this.flex);

  final String value;
  final Color color;
  final int flex;

  @override
  Widget build(BuildContext context) => _YearBodyCell(
    flex: flex,
    child: Text(
      value,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );
}
