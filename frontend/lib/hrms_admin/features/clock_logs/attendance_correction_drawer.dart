import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/hrms_clock_logs_api.dart';
import '../../../services/hrms_payroll_api.dart';

const _blue = Color(0xFF0B2C7B);
const _line = Color(0xFFDCE5F4);

Future<void> showAttendanceCorrectionDrawer(
  BuildContext context, {
  required int employeeId,
  required String employeeName,
  required String staffId,
  required String employeeRole,
  required DateTime initialMonth,
  required VoidCallback onChanged,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close attendance correction',
  barrierColor: const Color(0xA6000000),
  transitionDuration: const Duration(milliseconds: 260),
  pageBuilder: (context, _, __) => Align(
    alignment: Alignment.centerRight,
    child: _AttendanceCorrectionDrawer(
      employeeId: employeeId,
      employeeName: employeeName,
      staffId: staffId,
      employeeRole: employeeRole,
      initialMonth: initialMonth,
      onChanged: onChanged,
    ),
  ),
  transitionBuilder: (_, animation, __, child) => SlideTransition(
    position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    ),
    child: child,
  ),
);

class _AttendanceCorrectionDrawer extends StatefulWidget {
  const _AttendanceCorrectionDrawer({
    required this.employeeId,
    required this.employeeName,
    required this.staffId,
    required this.employeeRole,
    required this.initialMonth,
    required this.onChanged,
  });
  final int employeeId;
  final String employeeName;
  final String staffId;
  final String employeeRole;
  final DateTime initialMonth;
  final VoidCallback onChanged;

  @override
  State<_AttendanceCorrectionDrawer> createState() => _AttendanceCorrectionDrawerState();
}

class _AttendanceCorrectionDrawerState extends State<_AttendanceCorrectionDrawer> {
  late DateTime _month;
  late DateTime _focusDate;
  bool _loading = true;
  bool _saving = false;
  bool _legacyCorrectionOpen = false;
  String? _error;
  List<Map<String, dynamic>> _days = const [];
  Map<String, dynamic>? _payroll;
  Map<String, dynamic>? _employee;
  bool _hasSharedProjection = false;
  bool? _employeeActive;
  int _activeTab = 0;
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _payrollHistory = const [];
  final Map<String, Map<String, dynamic>> _detailsByDate = {};
  String? _expandedDate;
  String? _detailsError;
  bool _detailsLoading = false;
  Map<String, dynamic>? _selected;
  String _chosenStatus = 'present';
  String? _notice;
  final _reason = TextEditingController();
  final _dailyLogScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialMonth.year, widget.initialMonth.month);
    final today = DateTime.now();
    _focusDate = today.year == _month.year && today.month == _month.month
        ? DateTime(today.year, today.month, today.day)
        : _month;
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _dailyLogScrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final initialLoad = _days.isEmpty;
    setState(() {
      _loading = initialLoad;
      _error = null;
      _selected = null;
      _expandedDate = null;
      _detailsError = null;
      _detailsByDate.clear();
    });
    try {
      final data = await HrmsClockLogsApi.calendar(employeeId: widget.employeeId, month: _month);
      Map<String, dynamic>? payroll;
      List<Map<String, dynamic>> payrollHistory = const [];
      final projection = data['projection'];
      final hasSharedProjection = projection is Map;
      if (projection is Map) {
        payroll = Map<String, dynamic>.from(projection);
      }
      // Fallback for an older backend during a rolling restart. The normal
      // path above uses the calendar response's single shared projection.
      if (payroll == null) {
        try {
          final payrollData = await HrmsPayrollApi.list(year: _month.year, month: _month.month);
          final items = (payrollData['items'] as List? ?? const []).whereType<Map>();
          final item = items.firstWhere(
            (value) => '${value['employeeUserId']}' == '${widget.employeeId}',
            orElse: () => <dynamic, dynamic>{},
          );
          if (item.isNotEmpty) payroll = Map<String, dynamic>.from(item);
        } catch (_) {
          // Attendance remains available even if payroll is not configured yet.
        }
      }
      final employee = data['employee'];
      final profileId = employee is Map ? int.tryParse('${employee['profileId']}') : null;
      if (profileId != null && profileId > 0) {
        try { payrollHistory = await HrmsPayrollApi.payrollHistory(profileId: profileId); } catch (_) {}
      }
      // The history endpoint contains persisted payroll runs.  The selected
      // month is also a live projection while it is pending, so place that
      // backend result first rather than hiding the current calculation.
      if (payroll != null) {
        final current = <String, dynamic>{
          ...payroll,
          'year': _month.year,
          'month': _month.month,
        };
        payrollHistory = [
          current,
          ...payrollHistory.where((item) =>
              '${item['year']}-${item['month']}' != '${_month.year}-${_month.month}'),
        ];
      }
      if (!mounted) return;
      setState(() {
        _days = (data['days'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _payroll = payroll;
        _employee = employee is Map ? Map<String, dynamic>.from(employee) : null;
        _hasSharedProjection = hasSharedProjection;
        _employeeActive = _employee?['isActive'] == true;
        _requests = (data['requests'] as List? ?? const []).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
        _payrollHistory = payrollHistory;
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _select(Map<String, dynamic> day) {
    if (day['editable'] != true) return;
    final status = '${day['status']}'.toLowerCase();
    setState(() {
      _selected = day;
      _chosenStatus = status == 'present' ? 'absent' : 'present';
      _reason.clear();
      _notice = null;
    });
  }

  void _openLegacyCorrection(Map<String, dynamic> day) {
    if (day['editable'] != true) return;
    _select(day);
    setState(() => _legacyCorrectionOpen = true);
  }

  Future<void> _toggleDayDetails(Map<String, dynamic> day) async {
    final date = '${day['date']}';
    if (_expandedDate == date) {
      setState(() {
        _expandedDate = null;
        _detailsError = null;
      });
      return;
    }
    setState(() {
      _expandedDate = date;
      _detailsError = null;
    });
    if (_detailsByDate.containsKey(date)) return;
    setState(() => _detailsLoading = true);
    try {
      final details = await HrmsClockLogsApi.attendanceDetails(
        employeeId: widget.employeeId,
        date: DateTime.parse(date),
      );
      if (!mounted) return;
      setState(() => _detailsByDate[date] = details);
    } catch (_) {
      if (mounted) setState(() => _detailsError = 'Could not load attendance details.');
    } finally {
      if (mounted) setState(() => _detailsLoading = false);
    }
  }

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null || _saving) return;
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Enter an admin reason before saving.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await HrmsClockLogsApi.correctStatus(
        employeeId: widget.employeeId,
        date: DateTime.parse('${selected['date']}'),
        status: _chosenStatus,
        reason: reason,
      );
      if (!mounted) return;
      widget.onChanged();
      final warning = result['data'] is Map ? result['data']['warning']?.toString() : null;
      setState(() {
        _notice = warning ?? result['message']?.toString() ?? 'Attendance status corrected.';
      });
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      child: Stack(children: [
        SizedBox(
          width: double.infinity,
          child: Column(children: [
          _overviewHeader(),
          const Divider(height: 1, color: Color(0xFFE1E8F5)),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null && _days.isEmpty)
            Expanded(child: Center(child: TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(_error!))))
          else ...[
            Padding(padding: const EdgeInsets.fromLTRB(30, 10, 30, 20), child: _summary()),
            _tabs(),
            Expanded(
              child: Container(
                width: double.infinity,
                color: const Color(0xFFF7F9FE),
                padding: const EdgeInsets.fromLTRB(30, 28, 30, 26),
                child: LayoutBuilder(builder: (_, box) {
                  if (_activeTab == 1) return SingleChildScrollView(child: _leavePermissions());
                  if (_activeTab == 2) return SingleChildScrollView(child: _payrollHistoryView());
                  final leftPanel = Scrollbar(
                    controller: _dailyLogScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _dailyLogScrollController,
                      child: Column(children: [
                        _attendanceList(minHeight: box.maxHeight),
                      ]),
                    ),
                  );
                  if (box.maxWidth < 920) {
                    return Column(children: [Expanded(child: leftPanel), const SizedBox(height: 16), _rateCard()]);
                  }
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: leftPanel),
                    const SizedBox(width: 16),
                    SizedBox(width: 350, child: _rateCard()),
                  ]);
                }),
              ),
            ),
          ],
          ]),
        ),
        if (_legacyCorrectionOpen) _legacyCorrectionSidebar(),
      ]),
    ),
  );

  Widget _overviewHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(30, 18, 22, 16),
        child: Row(
          children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, color: Color(0xFF1769E0))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Clock logs  /  Employee overview', style: TextStyle(color: Color(0xFF5671A9), fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 13),
                  Row(children: [
                    Container(width: 73, height: 73, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFEAF1FF), borderRadius: BorderRadius.circular(14)), child: Text(_initials(), style: const TextStyle(color: Color(0xFF1769E0), fontWeight: FontWeight.w800, fontSize: 21))),
                    const SizedBox(width: 13),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Flexible(child: Text(_employeeName, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF10265C), fontSize: 22, fontWeight: FontWeight.w800))), if (_employeeActive != null) ...[const SizedBox(width: 10), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: _employeeActive! ? const Color(0xFFE2F8E8) : const Color(0xFFFFE7E8), borderRadius: BorderRadius.circular(14)), child: Text(_employeeActive! ? 'Active' : 'Inactive', style: TextStyle(color: _employeeActive! ? const Color(0xFF118839) : const Color(0xFFC62828), fontWeight: FontWeight.w700, fontSize: 13)))]]),
                      Text('ID $_employeeStaffId · $_employeeRole', style: const TextStyle(color: Color(0xFF5870A2), fontSize: 14)),
                    ])),
                  ]),
                ],
              ),
            ),
            _ProfileDateNavigator(
              date: _focusDate,
              enabled: !_saving,
              onPrevious: () => _moveFocusDate(-1),
              onNext: () => _moveFocusDate(1),
              onPick: _pickFocusDate,
            ),
          ],
        ),
      );

  Future<void> _pickFocusDate() async {
    final picked = await showDatePicker(context: context, initialDate: _focusDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked != null) _setFocusDate(picked);
  }

  void _moveFocusDate(int days) => _setFocusDate(_focusDate.add(Duration(days: days)));

  void _setFocusDate(DateTime value) {
    final next = DateTime(value.year, value.month, value.day);
    final monthChanged = next.year != _month.year || next.month != _month.month;
    setState(() {
      _focusDate = next;
      if (monthChanged) _month = DateTime(next.year, next.month);
    });
    if (monthChanged) _load();
  }

  String _initials() {
    final words = _employeeName.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((word) => word[0].toUpperCase()).join();
  }

  String get _employeeName {
    final name = _employee?['name']?.toString().trim() ?? '';
    return name.isNotEmpty ? name : widget.employeeName;
  }

  String get _employeeStaffId {
    final id = _employee?['staffId']?.toString().trim() ?? '';
    return id.isNotEmpty ? id : widget.staffId;
  }

  String get _employeeRole {
    final role = _employee?['role']?.toString().trim() ?? '';
    if (role.isNotEmpty) return role;
    return widget.employeeRole.trim().isEmpty ? 'Employee' : widget.employeeRole;
  }

  int get _working => _days.where((d) { final s='${d['status']}'.toLowerCase(); return !['weekly off','holiday','future','outside employment'].contains(s); }).length;
  int _count(String value) => _days.where((d) => '${d['status']}'.toLowerCase() == value).length;
  int _payrollCount(String key, int fallback) {
    final value = _payroll?[key];
    return value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
  }
  int _sharedAttendanceCount(String payrollKey, String dayStatus) =>
      _hasSharedProjection ? _payrollCount(payrollKey, _count(dayStatus)) : _count(dayStatus);
  num get _calendarPaidUnits => _days.fold<num>(0, (total, day) {
    final units = day['paidUnits'];
    if (units is num) return total + units;
    final status = '${day['status']}'.toLowerCase();
    return total + (status == 'present' || status == 'late' ? 1 : status == 'half leave' ? .5 : 0);
  });
  String _numberLabel(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  Widget _summary() => LayoutBuilder(builder: (_, box) {
    final workingDays = _payrollCount('workingDays', _working);
    final paidDays = _hasSharedProjection
        ? (_payroll?['paidDays'] as num? ?? _calendarPaidUnits)
        : _calendarPaidUnits;
    final presentDays = _sharedAttendanceCount('presentDays', 'present');
    final lateDays = _sharedAttendanceCount('lateDays', 'late');
    final absentDays = _sharedAttendanceCount('absentDays', 'absent');
    final lopDays = _payrollCount('lopDays', 0);
    final permissionDays = _requests.where((request) => '${request['type']}'.toLowerCase() == 'permission' && '${request['status']}'.toLowerCase() == 'approved').length;
    final working = Container(height: 120, padding: const EdgeInsets.symmetric(horizontal: 24), decoration: BoxDecoration(color: const Color(0xFF1760E9), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.calendar_month_outlined, color: Colors.white, size: 31), const SizedBox(width: 18), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Working days', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)), Text('$workingDays', style: const TextStyle(color: Colors.white, fontSize: 45, height: 1.05, fontWeight: FontWeight.w800))])), Container(height: 60, width: 1, color: Colors.white38), const SizedBox(width: 26), Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [const Text('Paid days', style: TextStyle(color: Colors.white70, fontSize: 15)), Text('${_numberLabel(paidDays)} / $workingDays', style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800))]) ]));
    final payrollStatus = _payroll?['status']?.toString() ?? 'Not available';
    final payrollAmount = _payroll?['netPayLabel']?.toString() ?? '—';
    final attendance = Container(height: 120, padding: const EdgeInsets.fromLTRB(18, 14, 18, 11), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Attendance · ${DateFormat('MMMM yyyy').format(_month)}', style: const TextStyle(color: Color(0xFF132C63), fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 6), Expanded(child: Row(children: [_stat('●  Present', presentDays, const Color(0xFF078A48)), _stat('●  Late', lateDays, const Color(0xFFEA8500)), _stat('●  Absent', absentDays, const Color(0xFFD93242)), _stat('●  LOP', lopDays, const Color(0xFFFF5870)), _stat('●  Permission', permissionDays, const Color(0xFF6931E7))]))]));
    final payroll = Container(height: 120, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text('Payroll · ${DateFormat('MMMM yyyy').format(_month)}', style: const TextStyle(color: Color(0xFF132C63), fontSize: 18, fontWeight: FontWeight.w800)), const Spacer(), _chip(payrollStatus, const Color(0xFFF0F3FA), const Color(0xFF506493))]), const Spacer(), Row(children: [const Icon(Icons.description_outlined, color: Color(0xFF6177A5)), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Net pay', style: TextStyle(color: Color(0xFF6B80AB))), Text(payrollAmount, style: const TextStyle(color: Color(0xFF10265C), fontSize: 20, fontWeight: FontWeight.w800))])]) ]));
    if (box.maxWidth < 1080) return Column(children: [working, const SizedBox(height: 14), attendance, const SizedBox(height: 14), payroll]);
    return Row(children: [Expanded(flex: 34, child: working), const SizedBox(width: 14), Expanded(flex: 47, child: attendance), const SizedBox(width: 14), Expanded(flex: 30, child: payroll)]);
  });
  Widget _stat(String name, int value, Color color) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF6980AE), fontSize: 12)), const SizedBox(height: 2), Text('$value', style: TextStyle(color: color, fontSize: 24, height: 1, fontWeight: FontWeight.w800))]));
  Widget _chip(String text, Color fill, Color ink) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(7)), child: Text(text, style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 12)));
  Widget _tabs() => Container(
    height: 56,
    width: double.infinity,
    padding: const EdgeInsets.only(left: 50),
    decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFF273142), width: .6))),
    child: Row(children: [
      _OverviewTab(icon: Icons.calendar_month_outlined, label: 'Attendance', active: _activeTab == 0, onTap: () => setState(() => _activeTab = 0)),
      SizedBox(width: 38),
      _OverviewTab(icon: Icons.description_outlined, label: 'Leaves & Permissions', active: _activeTab == 1, onTap: () => setState(() => _activeTab = 1)),
      SizedBox(width: 38),
      _OverviewTab(icon: Icons.history, label: 'Payroll History', active: _activeTab == 2, onTap: () => setState(() => _activeTab = 2)),
    ]),
  );
  Widget _attendanceList({double? minHeight}) => Container(
    constraints: minHeight == null ? null : BoxConstraints(minHeight: minHeight!),
    decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(30, 20, 30, 16), child: Row(children: [const Text('Daily log', style: TextStyle(color: Color(0xFF293F82), fontSize: 20, fontWeight: FontWeight.w800)), Container(width: 1, height: 21, margin: const EdgeInsets.symmetric(horizontal: 16), color: Color(0xFFD6DFEF)), Text(DateFormat('MMMM yyyy').format(_month), style: const TextStyle(color: Color(0xFF8A98B4), fontSize: 16))])),
      Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(34, 8, 18, 8), color: const Color(0xFFF8FAFF), child: Text('WEEK · ${DateFormat('MMM d').format(_month)} – ${DateFormat('MMM d').format(DateTime(_month.year, _month.month + 1, 0))}', style: const TextStyle(color: Color(0xFF7183A9), fontSize: 12, fontWeight: FontWeight.w800))),
      ..._days.expand((day) => _attendanceRow(day)),
    ]),
  );

  List<Widget> _attendanceRow(Map<String, dynamic> day) {
    final date = '${day['date']}';
    final status = '${day['status']}';
    final badge = _badge(status);
    final details = _detailsByDate[date];
    final expanded = _expandedDate == date;
    return [
      InkWell(
        onTap: () => _toggleDayDetails(day),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE6ECF6)))),
          child: Row(children: [
            SizedBox(width: 105, child: Row(children: [const Icon(Icons.circle, size: 10, color: Color(0xFF1769E0)), const SizedBox(width: 13), Text('${day['day'] ?? ''}\n${DateFormat('EEE').format(DateTime.parse(date))}', style: const TextStyle(color: Color(0xFF1769E0), fontSize: 16, fontWeight: FontWeight.w800))])),
            Expanded(child: _cell('Check in', '${day['checkIn'] ?? '—'}')),
            Expanded(child: _cell('Check out', '${day['checkOut'] ?? '—'}')),
            Expanded(child: _cell('Worked', _duration(details?['workingMinutes']))),
            Expanded(child: _cell('Break', _duration(details?['breakMinutes']))),
            SizedBox(width: 150, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Status', style: TextStyle(color: Color(0xFF7285AC), fontSize: 12)), const SizedBox(height: 5), Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: badge.$1, borderRadius: BorderRadius.circular(7)), child: Text(status, style: TextStyle(color: badge.$2, fontWeight: FontWeight.w700, fontSize: 12)))])),
            IconButton(onPressed: day['editable'] == true ? () => _openLegacyCorrection(day) : null, icon: Icon(Icons.edit_calendar_outlined, color: day['editable'] == true ? const Color(0xFF1769E0) : const Color(0xFFB2BDCF)), tooltip: day['editable'] == true ? 'Correct attendance' : 'This date cannot be corrected'),
            const SizedBox(width: 4),
            IconButton(onPressed: () => _toggleDayDetails(day), icon: Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: const Color(0xFF1769E0)), tooltip: expanded ? 'Hide details' : 'Show details'),
          ]),
        ),
      ),
      if (expanded) _expandedAttendanceDetails(day, details),
    ];
  }

  Widget _expandedAttendanceDetails(Map<String, dynamic> day, Map<String, dynamic>? details) {
    if (_detailsLoading && details == null) return const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator()));
    if (_detailsError != null && details == null) return Padding(padding: const EdgeInsets.all(16), child: Text(_detailsError!, style: const TextStyle(color: Color(0xFFC62828))));
    final breaks = (details?['breaks'] as List? ?? const []).whereType<Map>().toList();
    final firstBreak = breaks.isEmpty ? const <String, dynamic>{} : Map<String, dynamic>.from(breaks.first);
    return Container(
      margin: const EdgeInsets.fromLTRB(62, 0, 30, 12),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFF), border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Expanded(child: _cell('Break start', _displayTime(firstBreak['startedAt']))),
        Expanded(child: _cell('Break end', _displayTime(firstBreak['endedAt']))),
        Expanded(child: _cell('Method', '${details?['workMode'] ?? '—'}')),
        Expanded(child: _cell('LOP', '${'${day['status']}'.toLowerCase() == 'absent' ? 'Yes' : 'No'}')),
      ]),
    );
  }

  String _duration(dynamic minutes) {
    final total = minutes is num ? minutes.toInt() : int.tryParse('$minutes') ?? 0;
    if (total <= 0) return '—';
    return '${total ~/ 60}h ${total % 60}m';
  }

  String _displayTime(dynamic value) {
    if (value == null || '$value'.isEmpty) return '—';
    final parsed = DateTime.tryParse('$value');
    return parsed == null ? '$value' : DateFormat('h:mm a').format(parsed);
  }

  Widget _leavePermissions() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.only(bottom: 24), child: Row(children: [const Text('Leaves & Permissions', style: TextStyle(color: Color(0xFF10265C), fontSize: 22, fontWeight: FontWeight.w800)), Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 18), color: Color(0xFFD6DFEF)), Text(DateFormat('MMMM yyyy').format(_month), style: const TextStyle(color: Color(0xFF8795B0), fontSize: 17))])),
    if (_requests.isEmpty) _emptyTab('No leave or permission requests for this month.') else ..._requests.map(_requestCard),
  ]);

  Widget _requestCard(Map<String, dynamic> request) {
    final status = '${request['status'] ?? 'Pending'}';
    final type = '${request['type'] ?? 'Request'}';
    final date = DateTime.tryParse('${request['date'] ?? ''}');
    final statusColors = status.toLowerCase() == 'approved' ? (const Color(0xFFE2F8E8), const Color(0xFF118839)) : status.toLowerCase() == 'rejected' ? (const Color(0xFFFFE6E8), const Color(0xFFC62828)) : (const Color(0xFFFFEEDC), const Color(0xFFE06E00));
    return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(11)), child: Row(children: [
      Container(width: 68, height: 76, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFF1769E0), borderRadius: BorderRadius.circular(11)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(date == null ? '—' : DateFormat('dd').format(date), style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800)), Text(date == null ? '' : DateFormat('MMM yyyy').format(date), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))])),
      const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text(toBeginningOfSentenceCase(type) ?? type, style: const TextStyle(color: Color(0xFF112A63), fontSize: 16, fontWeight: FontWeight.w800))), _chip(status, statusColors.$1, statusColors.$2)]), const SizedBox(height: 5), Text('${date == null ? '—' : DateFormat('dd MMM yyyy').format(date)}${request['startTime'] != null ? '  ·  ${request['startTime']} – ${request['endTime']}' : ''}', style: const TextStyle(color: Color(0xFF7586A8), fontSize: 12)), if ('${request['reason'] ?? ''}'.trim().isNotEmpty) Container(width: double.infinity, margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFEAF1FF), borderRadius: BorderRadius.circular(7)), child: Text('${request['reason']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF314C86), fontSize: 12))) ])),
      const SizedBox(width: 18), _requestMetric(Icons.calendar_month_outlined, 'Applied', date == null ? '—' : DateFormat('dd MMM yyyy').format(date)), const SizedBox(width: 20), _requestMetric(Icons.person_outline, 'Reviewer', '${request['reviewedBy'] ?? '—'}'), const SizedBox(width: 20), _requestMetric(Icons.account_balance_wallet_outlined, 'Payroll', '${request['salaryMode'] ?? '—'}'),
    ]));
  }

  Widget _requestMetric(IconData icon, String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, size: 18, color: const Color(0xFF1769E0)), const SizedBox(width: 8), Text(label, style: const TextStyle(color: Color(0xFF8795B0), fontSize: 14))]), const SizedBox(height: 8), Text(value, style: const TextStyle(color: Color(0xFF142C63), fontSize: 15, fontWeight: FontWeight.w700))]);

  Widget _payrollHistoryView() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    if (_payrollHistory.isEmpty) _emptyTab('No payroll details are available for this employee.') else ..._payrollHistory.take(6).map(_payrollHistoryCard),
  ]);

  Widget _payrollHistoryCard(Map<String, dynamic> item) {
    final month = DateTime(int.tryParse('${item['year']}') ?? _month.year, int.tryParse('${item['month']}') ?? _month.month);
    final status = '${item['status'] ?? 'Pending'}';
    final paid = status.toLowerCase() == 'paid';
    num number(dynamic value) {
      if (value is num) return value;
      final cleaned = '$value'.replaceAll(RegExp(r'[^0-9.-]'), '');
      return num.tryParse(cleaned) ?? 0;
    }
    String money(dynamic value) => '₹${number(value).toStringAsFixed(0)}';
    // History persists totalDeduction. The live projection carries its late
    // and absence components separately, so calculate the same displayed
    // total without relying on an empty client-side placeholder.
    final totalDeduction = item['totalDeduction'] ??
        (number(item['lateDeductions'] ?? item['deductions']) + number(item['absentDeductions']));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(11)),
      child: Row(children: [
        Container(width: 74, height: 84, alignment: Alignment.center, decoration: const BoxDecoration(color: Color(0xFFEAF1FF), border: Border(left: BorderSide(color: Color(0xFF1769E0), width: 4))), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(DateFormat('MMM').format(month).toUpperCase(), style: const TextStyle(color: Color(0xFF1769E0), fontSize: 12, fontWeight: FontWeight.w800)), Text('${month.year}', style: const TextStyle(color: Color(0xFF142C63), fontSize: 19, fontWeight: FontWeight.w800))])),
        const SizedBox(width: 14),
        Expanded(child: Text(DateFormat('MMMM yyyy').format(month), style: const TextStyle(color: Color(0xFF10265C), fontSize: 17, fontWeight: FontWeight.w800))),
        _chip(status, paid ? const Color(0xFFE2F8E8) : const Color(0xFFFFEEDC), paid ? const Color(0xFF118839) : const Color(0xFFE06E00)),
        const SizedBox(width: 14),
        OutlinedButton.icon(
          onPressed: () => _showDayWisePayroll(item, month),
          icon: const Icon(Icons.receipt_long_outlined, size: 17),
          label: const Text('View day-wise payroll'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF1769E0),
            side: const BorderSide(color: Color(0xFFBBD0FA)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
        const SizedBox(width: 14),
        _historyMetric('Working', '${item['workingDays'] ?? 0}'),
        _historyMetric('Paid days', '${item['paidDays'] ?? 0}'),
        _historyMetric('LOP', '${item['lopDays'] ?? 0}', ink: const Color(0xFFD93445)),
        const SizedBox(width: 18),
        Container(width: 190, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF1F5FD), borderRadius: BorderRadius.circular(9)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Net pay', style: TextStyle(color: Color(0xFF8190AC), fontSize: 12)),
          Text(money(item['netPay']), style: const TextStyle(color: Color(0xFF142C63), fontSize: 18, fontWeight: FontWeight.w800)),
          const Divider(),
          Row(children: [Expanded(child: _historyAmount('Salary', money(item['salary'] ?? item['monthlySalary']))), Expanded(child: _historyAmount('Deduction', money(totalDeduction)))]),
        ])),
      ]),
    );
  }

  Future<void> _showDayWisePayroll(Map<String, dynamic> item, DateTime month) => showDialog<void>(
    context: context,
    builder: (_) => _DayWisePayrollDialog(
      employeeId: widget.employeeId,
      profileId: int.tryParse('${_employee?['profileId'] ?? item['profileId'] ?? 0}') ?? 0,
      employeeName: _employeeName,
      staffId: _employeeStaffId,
      month: month,
      fallbackPayroll: item,
    ),
  );

  Widget _historyMetric(String label, String value, {Color ink = const Color(0xFF142C63)}) => SizedBox(width: 78, child: Column(children: [Text(label, style: const TextStyle(color: Color(0xFF8795B0), fontSize: 12)), const SizedBox(height: 5), Text(value, style: TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w800))]));
  Widget _historyAmount(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Color(0xFF8190AC), fontSize: 11)), const SizedBox(height: 3), Text(value, style: const TextStyle(color: Color(0xFF142C63), fontSize: 13, fontWeight: FontWeight.w800))]);
  Widget _emptyTab(String text) => Container(width: double.infinity, padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(12)), child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF7586A8), fontSize: 16)));
  Widget _cell(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Color(0xFF7285AC), fontSize: 12)), const SizedBox(height: 5), Text(value, style: const TextStyle(color: Color(0xFF17336B), fontWeight: FontWeight.w600))]);
  Widget _rateCard() {
    final present = _sharedAttendanceCount('presentDays', 'present');
    final late = _sharedAttendanceCount('lateDays', 'late');
    final absent = _sharedAttendanceCount('absentDays', 'absent');
    final workingDays = _payrollCount('workingDays', _working);
    final rate = workingDays == 0 ? 0 : (((present + late) / workingDays) * 100).round();
    return Container(
      height: 350,
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 20),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Attendance rate', style: TextStyle(color: Color(0xFF10265C), fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        Center(child: SizedBox(width: 120, height: 120, child: Stack(alignment: Alignment.center, children: [
          SizedBox(width: 120, height: 120, child: CircularProgressIndicator(value: rate / 100, strokeWidth: 13, strokeCap: StrokeCap.round, backgroundColor: const Color(0xFFE2ECFC), color: const Color(0xFF1162F0))),
          Column(mainAxisSize: MainAxisSize.min, children: [Text('$rate%', style: const TextStyle(color: Color(0xFF1162F0), fontSize: 30, height: 1, fontWeight: FontWeight.w800)), const SizedBox(height: 5), const Text('present', style: TextStyle(color: Color(0xFF8593AE), fontSize: 14))]),
        ]))),
        const Spacer(),
        _rateLegend('Present', '$present ${present == 1 ? 'day' : 'days'}', const Color(0xFF078A48)),
        const SizedBox(height: 12),
        _rateLegend('Late', '$late ${late == 1 ? 'day' : 'days'}', const Color(0xFFE57A00)),
        const SizedBox(height: 12),
        _rateLegend('Absent', '$absent ${absent == 1 ? 'day' : 'days'}', const Color(0xFFD93242)),
      ]),
    );
  }

  Widget _rateLegend(String label, String value, Color color) => Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 10), Text(label, style: const TextStyle(color: Color(0xFF8190AC), fontSize: 16)), const Spacer(), Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16))]);

  Widget _legacyCorrectionSidebar() => Align(
    alignment: Alignment.centerRight,
    child: Material(
      color: Colors.white,
      elevation: 24,
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 440,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 14),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$_employeeName — ${DateFormat('MMMM yyyy').format(_month)}', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF1C315E), fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('$_employeeRole · Employee ID: $_employeeStaffId', style: const TextStyle(color: Color(0xFF6374A5), fontSize: 12)),
              ])),
              IconButton(onPressed: () => setState(() => _legacyCorrectionOpen = false), icon: const Icon(Icons.close, color: Color(0xFF657080))),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFE7EAF0)),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(12, 14, 12, 22), child: Column(children: [
            _monthControl(),
            const SizedBox(height: 10),
            _calendar(),
            const SizedBox(height: 16),
            _correctionPanel(),
          ]))),
        ]),
      ),
    ),
  );

  Widget _monthControl() => Row(children: [
    IconButton(onPressed: _saving ? null : () { setState(() => _month = DateTime(_month.year, _month.month - 1)); _load(); }, icon: const Icon(Icons.chevron_left, color: Color(0xFF647084))),
    Expanded(child: Text(DateFormat('MMMM yyyy').format(_month), textAlign: TextAlign.center,
        style: const TextStyle(color: _blue, fontSize: 18, fontWeight: FontWeight.w700))),
    IconButton(onPressed: _saving ? null : () { setState(() => _month = DateTime(_month.year, _month.month + 1)); _load(); }, icon: const Icon(Icons.chevron_right, color: Color(0xFF647084))),
  ]);

  Widget _calendar() {
    if (_loading) return const SizedBox(height: 360, child: Center(child: CircularProgressIndicator()));
    if (_error != null && _days.isEmpty) return SizedBox(height: 250, child: Center(child: TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(_error!))));
    final first = DateTime(_month.year, _month.month).weekday % 7;
    final cells = <Widget>[...List.generate(first, (_) => const SizedBox())];
    cells.addAll(_days.map(_dayCell));
    return Column(children: [
      const Row(children: [
        _Weekday('Sun'), _Weekday('Mon'), _Weekday('Tue'), _Weekday('Wed'), _Weekday('Thu'), _Weekday('Fri'), _Weekday('Sat'),
      ]),
      const SizedBox(height: 6),
      GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: .92, children: cells),
    ]);
  }

  Widget _dayCell(Map<String, dynamic> day) {
    final selected = _selected?['date'] == day['date'];
    final status = '${day['status']}';
    final style = _badge(status);
    return InkWell(
      onTap: _saving ? null : () => _select(day),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: selected ? const Color(0xFF1769E0) : _line, width: selected ? 1.6 : 1),
        ),
        child: Column(children: [
          Text('${day['day']}', style: TextStyle(color: selected ? const Color(0xFF1769E0) : _blue, fontWeight: FontWeight.w600)),
          const SizedBox(height: 7),
          if (status != 'No record') Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            decoration: BoxDecoration(color: style.$1, borderRadius: BorderRadius.circular(3)),
            child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: TextStyle(color: style.$2, fontSize: 8, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  (Color, Color) _badge(String status) {
    final value = status.toLowerCase();
    if (value == 'present') return (const Color(0xFFDDF6EA), const Color(0xFF078A48));
    if (value == 'absent' || value == 'no record') return (const Color(0xFFFFE6E8), const Color(0xFFD93445));
    if (value == 'late' || value == 'early exit') return (const Color(0xFFFFEDD9), const Color(0xFFE16E00));
    if (value == 'leave' || value == 'holiday') return (const Color(0xFFF0E5FF), const Color(0xFF7B3FBE));
    return (const Color(0xFFEDF0F5), const Color(0xFF657080));
  }

  Widget _correctionPanel() {
    final day = _selected;
    if (day == null) {
      return Column(children: [
        if (_notice != null) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F8EF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_notice!, style: const TextStyle(color: Color(0xFF078A48), fontSize: 13)),
          ),
        ],
        _message('Select a date to see its attendance and make a correction.'),
      ]);
    }
    if (day['editable'] != true) return _message('This date cannot be corrected here\n(future date, leave, holiday, weekly off, or outside employment date).');
    final status = '${day['status']}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Correct attendance — ${day['date']}', style: const TextStyle(color: _blue, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _detail('Current', status), _detail('Check in', '${day['checkIn'] ?? '—'}'), _detail('Check out', '${day['checkOut'] ?? '—'}'),
        if (day['adminReason'] != null) _detail('Previous Admin reason', '${day['adminReason']}'),
        const SizedBox(height: 13),
        Row(children: [
          _statusChoice('present', 'Present', const Color(0xFF078A48)),
          const SizedBox(width: 9),
          _statusChoice('absent', 'Absent', const Color(0xFFD93445)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _reason,
          enabled: !_saving,
          maxLength: 1000,
          minLines: 3,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Admin reason', hintText: 'Explain why this status is being corrected',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 9), child: Text(_error!, style: const TextStyle(color: Color(0xFFC62828), fontSize: 12))),
        SizedBox(width: double.infinity, height: 43, child: FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1769E0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Save Correction'),
        )),
      ]),
    );
  }

  Widget _message(String text) => Container(
    width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
    decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(12)),
    child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF4E5A70), fontSize: 15, height: 1.45)),
  );

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: RichText(text: TextSpan(style: const TextStyle(color: Color(0xFF4E5A70), fontSize: 13), children: [
      TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: value),
    ])),
  );

  Widget _statusChoice(String value, String label, Color color) => ChoiceChip(
    label: Text(label), selected: _chosenStatus == value, onSelected: _saving ? null : (_) => setState(() => _chosenStatus = value),
    selectedColor: color.withValues(alpha: .13), side: BorderSide(color: _chosenStatus == value ? color : _line),
    labelStyle: TextStyle(color: _chosenStatus == value ? color : const Color(0xFF4E5A70), fontWeight: FontWeight.w600),
  );
}

class _DayWisePayrollDialog extends StatefulWidget {
  const _DayWisePayrollDialog({
    required this.employeeId,
    required this.profileId,
    required this.employeeName,
    required this.staffId,
    required this.month,
    required this.fallbackPayroll,
  });

  final int employeeId;
  final int profileId;
  final String employeeName;
  final String staffId;
  final DateTime month;
  final Map<String, dynamic> fallbackPayroll;

  @override
  State<_DayWisePayrollDialog> createState() => _DayWisePayrollDialogState();
}

class _DayWisePayrollDialogState extends State<_DayWisePayrollDialog> {
  late Future<Map<String, dynamic>> _future;
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.month.year, widget.month.month);
    _future = _load();
  }

  List<DateTime> get _months {
    final months = List<DateTime>.generate(12, (index) =>
        DateTime(DateTime.now().year, DateTime.now().month - index));
    if (!months.any((value) => value.year == _month.year && value.month == _month.month)) {
      months.add(_month);
      months.sort((a, b) => b.compareTo(a));
    }
    return months;
  }

  void _selectMonth(DateTime month) {
    setState(() {
      _month = DateTime(month.year, month.month);
      _future = _load();
    });
  }

  Future<Map<String, dynamic>> _load() async {
    Map<String, dynamic>? calendar;
    Map<String, dynamic>? ledger;
    try {
      calendar = await HrmsClockLogsApi.calendar(
        employeeId: widget.employeeId,
        month: _month,
      );
    } catch (_) {
      // A saved payroll ledger remains available even if calendar refresh is
      // temporarily unavailable.
    }
    if (widget.profileId > 0) {
      try {
        ledger = await HrmsPayrollApi.deductionHistory(
          profileId: widget.profileId,
          year: _month.year,
          month: _month.month,
        );
      } catch (_) {
        // The calendar projection below is the normal live-period source.
      }
    }
    return {'calendar': calendar, 'ledger': ledger};
  }

  num _number(dynamic value) {
    if (value is num) return value;
    return num.tryParse('$value'.replaceAll(RegExp(r'[^0-9.-]'), '')) ?? 0;
  }

  String _money(dynamic value) => '₹${_number(value).toStringAsFixed(0)}';

  String _units(dynamic value) {
    final units = _number(value);
    return units == units.roundToDouble() ? units.toInt().toString() : units.toStringAsFixed(1);
  }

  (Color, Color) _statusStyle(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return (const Color(0xFFDDF6EA), const Color(0xFF078A48));
      case 'late':
      case 'early exit':
        return (const Color(0xFFFFEDD9), const Color(0xFFE16E00));
      case 'absent':
        return (const Color(0xFFFFE6E8), const Color(0xFFD93445));
      case 'on leave':
      case 'half leave':
        return (const Color(0xFFF0E5FF), const Color(0xFF7B3FBE));
      default:
        return (const Color(0xFFEDF0F5), const Color(0xFF657080));
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: const Color(0xFFF7F9FE),
        surfaceTintColor: const Color(0xFFF7F9FE),
        insetPadding: const EdgeInsets.symmetric(horizontal: 42, vertical: 34),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 720),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(height: 360, child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) {
                return SizedBox(
                  height: 260,
                  child: Center(
                    child: TextButton.icon(
                      onPressed: () => setState(() => _future = _load()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Could not load day-wise payroll. Retry'),
                    ),
                  ),
                );
              }
              final data = snapshot.data ?? const <String, dynamic>{};
              final calendar = data['calendar'];
              final calendarProjection = calendar is Map && calendar['projection'] is Map
                  ? Map<String, dynamic>.from(calendar['projection'] as Map)
                  : const <String, dynamic>{};
              final ledger = data['ledger'];
              final ledgerSummary = ledger is Map && ledger['summary'] is Map
                  ? Map<String, dynamic>.from(ledger['summary'] as Map)
                  : const <String, dynamic>{};
              final ledgerOverview = ledger is Map && ledger['overview'] is Map
                  ? Map<String, dynamic>.from(ledger['overview'] as Map)
                  : const <String, dynamic>{};
              final projection = calendarProjection.isNotEmpty
                  ? calendarProjection
                  : {...widget.fallbackPayroll, ...ledgerOverview, ...ledgerSummary};
              final calendarRows = (calendarProjection['dailyEntries'] as List? ?? const [])
                  .whereType<Map>()
                  .map((entry) => Map<String, dynamic>.from(entry))
                  .toList();
              final ledgerRows = (ledger is Map ? ledger['items'] : null) as List? ?? const [];
              final rows = calendarRows.isNotEmpty
                  ? calendarRows
                  : ledgerRows.whereType<Map>().map((entry) {
                      final item = Map<String, dynamic>.from(entry);
                      return <String, dynamic>{
                        'date': item['attendance_date'],
                        'status': item['attendance_status'],
                        'paidUnits': item['paid_units'],
                        'lopUnits': item['lop_units'],
                        'dailySalary': item['daily_salary'],
                        'absentAmount': item['absent_amount'],
                        'timeDeduction': item['time_deduction'] ?? item['late_deduction'],
                        'lateMinutes': item['late_minutes'],
                        'earlyExitMinutes': item['early_exit_minutes'],
                        'totalDeduction': item['total_deduction'],
                        'presentAmount': item['present_amount'],
                        'updatedSalary': item['updated_salary'],
                        'checkIn': item['check_in_at'],
                        'checkOut': item['check_out_at'],
                      };
                    }).toList();
              rows.sort((left, right) => '${right['date']}'.compareTo('${left['date']}'));
              return _content(projection, rows);
            },
          ),
        ),
      );

  Widget _content(Map<String, dynamic> payroll, List<Map<String, dynamic>> rows) {
    final companyHours = _companyHours(payroll);
    return ColoredBox(
      color: Colors.white,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 26, 24, 18),
          child: Row(children: [
            Text('${widget.employeeName} — Payroll history',
                style: const TextStyle(color: Color(0xFF10265C), fontSize: 25, fontWeight: FontWeight.w800)),
            const SizedBox(width: 18),
            _headerFact('Total salary', _money(payroll['monthlySalary'] ?? payroll['salary'])),
            if (companyHours != null) ...[
              const SizedBox(width: 10),
              _headerFact('Company hours', companyHours),
            ],
            const SizedBox(width: 10),
            _headerFact('Working days', _units(payroll['workingDays'])),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Color(0xFF657080)), tooltip: 'Close'),
          ]),
        ),
        const Divider(height: 1, color: _line),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 14, 28, 16),
          child: Row(children: [
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Payroll month', border: OutlineInputBorder()),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<DateTime>(
                    isExpanded: true,
                    value: _month,
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF657080)),
                    items: _months.map((month) => DropdownMenuItem(value: month, child: Text(DateFormat('MMMM yyyy').format(month), style: const TextStyle(color: Color(0xFF10265C), fontWeight: FontWeight.w600)))).toList(),
                    onChanged: (month) { if (month != null) _selectMonth(month); },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              onPressed: () => _selectMonth(_month),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh payroll'),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF17336B), side: const BorderSide(color: Color(0xFFD7E2F4)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
            ),
          ]),
        ),
        const Divider(height: 1, color: _line),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No payroll days are available for this period.', style: TextStyle(color: Color(0xFF7285AC))))
              : Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 18, 28, 12),
                    child: Column(children: [_tableHeader(), ...rows.map(_row)]),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
          child: Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))),
        ),
      ]),
    );
  }

  Widget _headerFact(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: const Color(0xFFF5F8FE), border: Border.all(color: const Color(0xFFD7E2F4)), borderRadius: BorderRadius.circular(9)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Color(0xFF7183A9), fontSize: 11, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(color: Color(0xFF10265C), fontSize: 14, fontWeight: FontWeight.w800)),
    ]),
  );

  String? _companyHours(Map<String, dynamic> payroll) {
    final start = '${payroll['shiftStart'] ?? ''}';
    final end = '${payroll['shiftEnd'] ?? ''}';
    final minutes = _number(payroll['shiftMinutes']);
    if (start.isEmpty || end.isEmpty || minutes <= 0) return null;
    final hours = minutes / 60;
    return '${_singleTime('2000-01-01 $start')} – ${_singleTime('2000-01-01 $end')} (${hours == hours.roundToDouble() ? hours.toInt() : hours.toStringAsFixed(1)}h)';
  }

  Widget _summaryMetric(String label, String value, {Color ink = const Color(0xFF10265C)}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFE3EAF6)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Color(0xFF8190AC), fontSize: 12)),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
        ),
      );

  Widget _tableHeader() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(color: const Color(0xFFF5F8FE), borderRadius: BorderRadius.circular(8)),
        child: const Row(children: [
          Expanded(flex: 11, child: _PayrollColumnHeader('Date')),
          Expanded(flex: 9, child: _PayrollColumnHeader('Salary')),
          Expanded(flex: 9, child: _PayrollColumnHeader('Check in')),
          Expanded(flex: 9, child: _PayrollColumnHeader('Check out')),
          Expanded(flex: 9, child: _PayrollColumnHeader('Status')),
          Expanded(flex: 14, child: _PayrollColumnHeader('Late deduction time')),
          Expanded(flex: 11, child: _PayrollColumnHeader('Late deduction')),
          Expanded(flex: 11, child: _PayrollColumnHeader('Absent amount')),
          Expanded(flex: 12, child: _PayrollColumnHeader('Total deduction')),
          Expanded(flex: 11, child: _PayrollColumnHeader('Present amount')),
        ]),
      );

  Widget _row(Map<String, dynamic> row) {
    final date = DateTime.tryParse('${row['date']}');
    final status = '${row['status'] ?? '—'}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFDCE5F4)))),
      child: Row(children: [
        Expanded(flex: 11, child: _PayrollColumnValue(date == null ? '—' : DateFormat('yyyy-MM-dd').format(date), bold: true)),
        Expanded(flex: 9, child: _PayrollColumnValue(_money(row['dailySalary']), bold: true)),
        Expanded(flex: 9, child: _PayrollColumnValue(_singleTime(row['checkIn']))),
        Expanded(flex: 9, child: _PayrollColumnValue(_singleTime(row['checkOut']))),
        Expanded(flex: 9, child: _PayrollColumnValue(status, bold: true)),
        Expanded(flex: 14, child: _PayrollColumnValue(_lateTime(row))),
        Expanded(flex: 11, child: _PayrollColumnValue(_money(row['timeDeduction']), color: const Color(0xFFE16E00), bold: true)),
        Expanded(flex: 11, child: _PayrollColumnValue(_money(row['absentAmount']), color: const Color(0xFFD93445), bold: true)),
        Expanded(flex: 12, child: _PayrollColumnValue(_money(row['totalDeduction']), bold: true)),
        Expanded(flex: 11, child: _PayrollColumnValue(_money(row['presentAmount']), color: const Color(0xFF078A48), bold: true)),
      ]),
    );
  }

  String _lateTime(Map<String, dynamic> row) {
    final minutes = _number(row['lateMinutes']) + _number(row['earlyExitMinutes']);
    return minutes <= 0 ? '—' : '${_units(minutes)} min';
  }

  String _singleTime(dynamic raw) {
    final parsed = DateTime.tryParse('${raw ?? ''}');
    return parsed == null ? '—' : DateFormat('h:mm a').format(parsed);
  }

  String _clockTime(dynamic checkIn, dynamic checkOut) {
    String value(dynamic raw) {
      final parsed = DateTime.tryParse('${raw ?? ''}');
      return parsed == null ? '—' : DateFormat('h:mm a').format(parsed);
    }
    final start = value(checkIn);
    final end = value(checkOut);
    return start == '—' && end == '—' ? '—' : '$start – $end';
  }
}

class _PayrollTableStyle {
  static const header = TextStyle(color: Color(0xFF7183A9), fontSize: 12, fontWeight: FontWeight.w800);
}

/// A flexible table cell for the payroll dialog.  The dialog deliberately
/// keeps every column inside its available width; long labels are shortened
/// instead of introducing a horizontal scrollbar.
class _PayrollColumnHeader extends StatelessWidget {
  const _PayrollColumnHeader(this.value);

  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _PayrollTableStyle.header,
        ),
      );
}

class _PayrollColumnValue extends StatelessWidget {
  const _PayrollColumnValue(
    this.value, {
    this.color = const Color(0xFF203967),
    this.bold = false,
  });

  final String value;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      );
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.icon, required this.label, this.active = false, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      height: 56,
      alignment: Alignment.center,
      decoration: active ? const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF1769E0), width: 3))) : null,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: active ? const Color(0xFF1769E0) : const Color(0xFF7B8AA6), size: 20),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(color: active ? const Color(0xFF1769E0) : const Color(0xFF7B8AA6), fontSize: 16, fontWeight: active ? FontWeight.w800 : FontWeight.w500)),
      ]),
    ),
  );
}

/// The single date navigator used by the shared employee overview, whether
/// it was opened from Clock Logs or from the Employees page.
class _ProfileDateNavigator extends StatelessWidget {
  const _ProfileDateNavigator({
    required this.date,
    required this.enabled,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });

  final DateTime date;
  final bool enabled;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Previous day',
        onPressed: enabled ? onPrevious : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 30, height: 38),
        icon: const Icon(Icons.chevron_left, size: 25),
      ),
      const SizedBox(width: 6),
      SizedBox(
        width: 210,
        height: 38,
        child: OutlinedButton.icon(
          onPressed: enabled ? onPick : null,
          icon: const Icon(Icons.calendar_month_outlined, size: 18),
          label: Text(DateFormat('d MMMM yyyy').format(date)),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF233B73),
            side: const BorderSide(color: Color(0xFFD8E1F0)),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
      ),
      const SizedBox(width: 6),
      IconButton(
        tooltip: 'Next day',
        onPressed: enabled ? onNext : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 30, height: 38),
        icon: const Icon(Icons.chevron_right, size: 25),
      ),
    ],
  );
}

class _Weekday extends StatelessWidget {
  const _Weekday(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF556A99), fontSize: 11)));
}
