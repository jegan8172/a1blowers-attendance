import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/api_config.dart';
import '../../services/auth_service.dart';
import '../shared/employee_ui.dart';

class EmployeeAttendancePage extends StatefulWidget {
  const EmployeeAttendancePage({super.key});

  @override
  State<EmployeeAttendancePage> createState() => _EmployeeAttendancePageState();
}

class _EmployeeAttendancePageState extends State<EmployeeAttendancePage> {
  final _attendanceKey = GlobalKey<_AttendanceViewState>();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthName = DateFormat('MMMM yyyy').format(now);

    return EmployeeScaffold(
      route: '/employee/attendance',
      title: 'Attendance Calendar',
      subtitle: 'Your attendance for $monthName',
      desktopHeaderAction: FilledButton.icon(
        onPressed: () => _attendanceKey.currentState?._requestCorrection(),
        style: FilledButton.styleFrom(
          backgroundColor: employeeBlue,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(Icons.edit_calendar_outlined),
        label: const Text('Request Correction'),
      ),
      desktop: _AttendanceView(key: _attendanceKey, mobile: false),
      mobile: const _AttendanceView(mobile: true),
    );
  }
}

class _AttendanceView extends StatefulWidget {
  const _AttendanceView({super.key, required this.mobile});
  final bool mobile;

  @override
  State<_AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<_AttendanceView> {
  late int year;
  late int month;
  bool _loading = false;
  Map<int, Map<String, dynamic>> _monthDays = {};
  int _presentCount = 0;
  int _absentCount = 0;
  int _lateCount = 0;
  int _workingDaysCount = 0;
  String? _token;
  DateTime? _selectedDate;

  static const monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    year = now.year;
    month = now.month;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = context.watch<AuthService>().token;
    if (_token != token) {
      _token = token;
      if (token != null && token.isNotEmpty) {
        _fetchMonthData();
      }
    }
  }

  String get monthLabel => '${monthNames[month - 1]} $year';
  String get monthQuery => '$year-${month.toString().padLeft(2, '0')}';

  int? _extractDay(dynamic rawWorkDate) {
    if (rawWorkDate == null) return null;
    final str = rawWorkDate.toString().trim();
    final match = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(str);
    if (match != null) {
      final recordYear = int.tryParse(match.group(1)!);
      final recordMonth = int.tryParse(match.group(2)!);
      final recordDay = int.tryParse(match.group(3)!);
      if (recordYear == year && recordMonth == month) return recordDay;
    }

    final parsed = DateTime.tryParse(str.replaceFirst(' ', 'T'));
    if (parsed != null && parsed.year == year && parsed.month == month) {
      return parsed.day;
    }
    return null;
  }

  Future<void> _fetchMonthData() async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    setState(() => _loading = true);
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/attendance/dashboard?month=$monthQuery');
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true && body['data'] != null) {
          final data = body['data'];
          final overview = data['month_overview'] as Map?;
          final Map<int, Map<String, dynamic>> daysMap = {};

          final records = data['month_records'] as List? ?? data['records'] as List?;
          if (records != null) {
            for (final item in records) {
              final dayNum = _extractDay(item['work_date'] ?? item['date']);
              if (dayNum != null) {
                final isLate = item['is_late'] == 1 || item['is_late'] == true || item['isLate'] == true;
                final statusStr = (item['attendance_status']?.toString() ?? item['status']?.toString() ?? '').toLowerCase();
                final isAbsent = statusStr == 'absent';
                final isHoliday = statusStr == 'holiday';
                final isWeeklyOff = statusStr == 'weekly_off' || statusStr == 'weekly off';
                final isHalfLeave = statusStr == 'half_leave';
                final leaveCode = {'earned_leave': 'EL', 'casual_leave': 'CL', 'sick_leave': 'SL', 'optional_holiday': 'OL', 'attendance_regularization': 'AR'}[statusStr];
                daysMap[dayNum] = {
                  'status': leaveCode ?? (isHoliday ? 'H' : (isWeeklyOff ? 'OFF' : (isHalfLeave ? 'HL' : (isAbsent ? 'A' : (isLate ? 'L' : 'P'))))),
                  'clock_in': item['clock_in_at'] ?? item['checkInAt'],
                  'clock_out': item['clock_out_at'] ?? item['checkOutAt'],
                };
              }
            }
          }

          final calendarData = data['calendarData'] as Map?;
          if (calendarData != null) {
            calendarData.forEach((rawDate, rawRecord) {
              if (rawRecord is! Map) return;
              final dayNum = _extractDay(rawDate);
              if (dayNum == null || daysMap.containsKey(dayNum)) return;
              final statusStr = (rawRecord['status']?.toString() ?? '').toLowerCase();
              final isLate = rawRecord['isLate'] == true || statusStr == 'late';
              daysMap[dayNum] = {
                'status': statusStr == 'holiday'
                    ? 'H'
                    : ((statusStr == 'weekly_off' || statusStr == 'weekly off') ? 'OFF' : (statusStr == 'half_leave' ? 'HL' : (statusStr == 'absent' ? 'A' : (isLate ? 'L' : 'P')))),
                'clock_in': rawRecord['checkInAt'] ?? rawRecord['checkIn'],
                  'clock_out': rawRecord['checkOutAt'] ?? rawRecord['checkOut'],
              };
            });
          }

          // Older backend instances return only the dashboard totals. Load the
          // employee's month history in that case so historical check-ins are
          // still read from attendance_records and shown in the calendar.
          if (daysMap.isEmpty) {
            final historyUrl = Uri.parse(
                '${ApiConfig.baseUrl}/attendance/me?month=$monthQuery');
            final historyResponse = await http.get(historyUrl, headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            }).timeout(const Duration(seconds: 15));

            if (historyResponse.statusCode == 200) {
              final historyBody = jsonDecode(historyResponse.body);
              final history = historyBody['data'];
              final historyRecords = history is Map ? history['records'] as List? : null;
              if (historyRecords != null) {
                for (final item in historyRecords) {
                  final dayNum = _extractDay(item['date'] ?? item['work_date']);
                  if (dayNum == null) continue;
                  final statusStr =
                      (item['status']?.toString() ?? '').toLowerCase();
                  final isLate = item['isLate'] == true || statusStr == 'late';
                  daysMap[dayNum] = {
                  'status': statusStr == 'holiday'
                        ? 'H'
                      : ((statusStr == 'weekly_off' || statusStr == 'weekly off') ? 'OFF' : (statusStr == 'half leave' || statusStr == 'half_leave'
                            ? 'HL'
                          : (statusStr == 'absent' ? 'A' : (isLate ? 'L' : 'P')))),
                    'clock_in': item['checkInAt'] ?? item['clock_in_at'],
                    'clock_out': item['checkOutAt'] ?? item['clock_out_at'],
                  };
                }
              }
            }
          }

          if (mounted) {
            setState(() {
              _presentCount = (overview?['present_days'] as num?)?.toInt() ?? 0;
              _absentCount = (overview?['absent_days'] as num?)?.toInt() ?? 0;
              _lateCount = (overview?['late_days'] as num?)?.toInt() ?? 0;
              _workingDaysCount = (overview?['work_time']?['working_days'] as num?)?.toInt() ?? daysMap.values.where((item) => item['status'] != 'OFF' && item['status'] != 'H').length;
              _monthDays = daysMap;
            });
          }
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void changeMonth(int offset) {
    setState(() {
      month += offset;
      if (month == 0) {
        month = 12;
        year--;
      } else if (month == 13) {
        month = 1;
        year++;
      }
    });
    _showMonthShiftToast('Loading $monthLabel...');
    _fetchMonthData();
  }

  void _showMonthShiftToast(String message) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _AttendanceToast(
        title: 'Month Shift',
        message: message,
        onDismissed: entry.remove,
      ),
    );
    overlay.insert(entry);
  }

  Map<String, dynamic> dataFor(int day) {
    if (_monthDays.containsKey(day)) {
      return _monthDays[day]!;
    }
    final isSunday = DateTime(year, month, day).weekday == DateTime.sunday;
    if (isSunday) {
      return {'status': 'OFF', 'clock_in': null};
    }
    return {'status': '', 'clock_in': null};
  }

  String _formatClock(dynamic value) {
    if (value == null || '$value'.trim().isEmpty) return '—';
    final raw = '$value'.trim();
    final match = RegExp(r'(?:^|[ T])(\d{2}):(\d{2})').firstMatch(raw);
    if (match == null) return raw;
    final hour = int.tryParse(match.group(1)!) ?? 0;
    final minute = match.group(2)!;
    return '${((hour + 11) % 12 + 1).toString().padLeft(2, '0')}:$minute ${hour >= 12 ? 'PM' : 'AM'}';
  }

  String _statusLabel(String status) => switch (status) {
    'P' => 'Present',
    'L' => 'Late',
    'A' => 'Absent',
    'HL' => 'Half leave',
    'OFF' => 'Weekly off',
    'H' => 'Holiday',
    'EL' => 'Earned leave',
    'CL' => 'Casual leave',
    'SL' => 'Sick leave',
    'OL' => 'Optional holiday',
    'AR' => 'Attendance regularization',
    _ => 'No attendance record',
  };

  void _showAttendanceDetails(int day) {
    final selected = DateTime(year, month, day);
    final info = dataFor(day);
    final status = '${info['status'] ?? ''}';
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss attendance details',
      barrierColor: const Color(0x990F172A),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, _, __) => _AttendanceDetailsSheet(
        mobile: isMobile,
        date: selected,
        status: status,
        statusLabel: _statusLabel(status),
        checkIn: _formatClock(info['clock_in']),
        checkOut: _formatClock(info['clock_out']),
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        if (!isMobile) return FadeTransition(opacity: curved, child: child);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
          child: child,
        );
      },
    );
  }

  Future<void> _requestCorrection() async {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final today = DateTime.now();
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    DateTime date = _selectedDate ??
        DateTime(year, month, today.day > lastDayOfMonth ? lastDayOfMonth : today.day);
    final startOfToday = DateTime(today.year, today.month, today.day);
    if (!date.isBefore(startOfToday)) {
      date = startOfToday.subtract(const Duration(days: 1));
    }
    final reason = TextEditingController();
    final checkIn = TextEditingController();
    final checkOut = TextEditingController();
    String type = 'incorrect_automatic_absence';
    bool isSubmitting = false;
    String? errorMessage;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss correction form',
      barrierColor: const Color(0x990F172A),
      transitionDuration: const Duration(milliseconds: 340),
      pageBuilder: (dialogContext, _, __) => StatefulBuilder(
        builder: (context, setDialogState) {
          const borderColor = Color(0xFFD6E1F4);
          final surfaceColor = isMobile ? Colors.white : const Color(0xFFF6F8FC);
          final fieldBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderColor),
          );
          final fieldDecoration = InputDecoration(
            filled: true,
            fillColor: surfaceColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            enabledBorder: fieldBorder,
            focusedBorder: fieldBorder.copyWith(
              borderSide: const BorderSide(color: Color(0xFF0969F9)),
            ),
          );
          Future<void> pickTime(TextEditingController controller, String label) async {
            if (isSubmitting) return;
            final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(controller.text.trim());
            final hour = int.tryParse(match?.group(1) ?? '');
            final minute = int.tryParse(match?.group(2) ?? '');
            final selected = await showTimePicker(
              context: dialogContext,
              initialTime: hour != null && minute != null && hour < 24 && minute < 60
                  ? TimeOfDay(hour: hour, minute: minute)
                  : TimeOfDay.now(),
              helpText: 'SELECT $label',
            );
            if (selected == null || !mounted) return;
            setDialogState(() {
              controller.text = '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
              errorMessage = null;
            });
          }

          return Dialog(
            alignment: isMobile ? Alignment.bottomCenter : null,
            insetPadding: isMobile
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 24),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: isMobile
                  ? const BorderRadius.vertical(top: Radius.circular(28))
                  : BorderRadius.circular(22),
            ),
            child: SizedBox(
              width: isMobile ? double.infinity : null,
              child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470),
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, isMobile ? 14 : 26, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isMobile)
                      Center(
                        child: Container(
                          width: 48,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFDBEAFE)),
                          ),
                          child: const Icon(Icons.edit_calendar_outlined,
                              color: employeeBlue, size: 21),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Request Correction',
                                  style: GoogleFonts.inter(
                                      color: employeeNavy,
                                      fontSize: isMobile ? 18 : 22,
                                      fontWeight: FontWeight.w800)),
                              if (isMobile)
                                Text('Submit missed punch or dispute',
                                    style: GoogleFonts.inter(
                                        color: employeeMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        if (isMobile)
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close_rounded),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFF1F5F9),
                              foregroundColor: employeeNavy,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: isMobile ? 20 : 30),
                    if (isMobile)
                      Text('Select Date', style: GoogleFonts.inter(color: employeeNavy, fontSize: 10, fontWeight: FontWeight.w700)),
                    if (isMobile) const SizedBox(height: 5),
                    InkWell(
                      onTap: isSubmitting
                          ? null
                          : () async {
                              final selected = await showDatePicker(
                                context: dialogContext,
                                initialDate: date,
                                firstDate: DateTime(2020),
                                lastDate: startOfToday.subtract(const Duration(days: 1)),
                              );
                              if (selected != null) {
                                setDialogState(() {
                                  date = selected;
                                  errorMessage = null;
                                });
                              }
                            },
                      child: Container(
                        padding: isMobile ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10) : EdgeInsets.zero,
                        decoration: isMobile ? BoxDecoration(border: Border.all(color: const Color(0xFFD6E1F4)), borderRadius: BorderRadius.circular(12)) : null,
                        child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isMobile)
                                  const Text('Attendance date',
                                      style: TextStyle(
                                          color: Color(0xFF66789B), fontSize: 13)),
                                if (!isMobile) const SizedBox(height: 3),
                                Text(
                                    isMobile
                                        ? DateFormat('dd-MM-yyyy').format(date)
                                        : DateFormat('dd MMM yyyy').format(date),
                                    style: const TextStyle(
                                        color: Color(0xFF0C1C49),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          const Icon(Icons.calendar_today_outlined,
                              color: Color(0xFF0969F9), size: 23),
                        ],
                        ),
                      ),
                    ),
                    SizedBox(height: isMobile ? 14 : 22),
                    if (isMobile)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text('Correction Type', style: GoogleFonts.inter(color: employeeNavy, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    SizedBox(
                      height: 48,
                      child: DropdownButtonFormField<String>(
                        value: type,
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down,
                            color: Color(0xFF62656A)),
                        style: const TextStyle(
                            color: Color(0xFF182238),
                            fontSize: 17,
                            fontWeight: FontWeight.w500),
                        decoration: fieldDecoration,
                        items: const [
                          DropdownMenuItem(
                              value: 'incorrect_automatic_absence',
                              child: Text('Incorrect automatic absence')),
                          DropdownMenuItem(
                              value: 'missing_check_in',
                              child: Text('Missing check-in')),
                          DropdownMenuItem(
                              value: 'missing_check_out',
                              child: Text('Missing check-out')),
                          DropdownMenuItem(value: 'incorrect_time', child: Text('Incorrect time')),
                        ],
                        onChanged: isSubmitting
                            ? null
                            : (value) => setDialogState(() => type = value!),
                      ),
                    ),
                    const SizedBox(height: 13),
                    if (type == 'missing_check_in' || type == 'incorrect_time') SizedBox(
                      height: 56,
                      child: TextField(
                        controller: checkIn,
                        enabled: !isSubmitting,
                        readOnly: true,
                        onTap: () => pickTime(checkIn, 'CHECK-IN TIME'),
                        style: const TextStyle(fontSize: 16),
                        decoration: fieldDecoration.copyWith(
                          hintText: 'Correct check-in time (HH:MM)',
                          hintStyle: const TextStyle(
                              color: Color(0xFF667089), fontSize: 16),
                          suffixIcon: IconButton(
                            tooltip: 'Select time',
                            onPressed: isSubmitting ? null : () => pickTime(checkIn, 'CHECK-IN TIME'),
                            icon: const Icon(Icons.schedule_outlined,
                                color: Color(0xFF0969F9), size: 23),
                          ),
                        ),
                      ),
                    ),
                    if (type == 'missing_check_in' || type == 'incorrect_time') const SizedBox(height: 13),
                    if (type == 'missing_check_out' || type == 'incorrect_time') SizedBox(
                      height: 56,
                      child: TextField(
                        controller: checkOut,
                        enabled: !isSubmitting,
                        readOnly: true,
                        onTap: () => pickTime(checkOut, 'CHECK-OUT TIME'),
                        style: const TextStyle(fontSize: 16),
                        decoration: fieldDecoration.copyWith(
                          hintText: 'Correct check-out time (HH:MM)',
                          hintStyle: const TextStyle(color: Color(0xFF667089), fontSize: 16),
                          suffixIcon: IconButton(
                            tooltip: 'Select time',
                            onPressed: isSubmitting ? null : () => pickTime(checkOut, 'CHECK-OUT TIME'),
                            icon: const Icon(Icons.schedule_outlined, color: Color(0xFF0969F9), size: 23),
                          ),
                        ),
                      ),
                    ),
                    if (type == 'missing_check_out' || type == 'incorrect_time') const SizedBox(height: 13),
                    if (isMobile)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text('Reason / Notes', style: GoogleFonts.inter(color: employeeNavy, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    SizedBox(
                      height: 70,
                      child: TextField(
                        controller: reason,
                        enabled: !isSubmitting,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(fontSize: 16),
                        decoration: fieldDecoration.copyWith(
                          contentPadding: const EdgeInsets.fromLTRB(16, 13, 16, 10),
                          hintText: 'Reason for this correction',
                          hintStyle: const TextStyle(
                              color: Color(0xFF182238), fontSize: 16),
                        ),
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(errorMessage!,
                          style: const TextStyle(
                              color: Color(0xFFC62828), fontSize: 13)),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: isMobile ? Alignment.center : Alignment.centerRight,
                      child: Row(
                        mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
                        children: [
                          if (!isMobile) TextButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.pop(dialogContext),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF667089),
                              textStyle: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            child: const Text('Cancel'),
                          ),
                          if (!isMobile) const SizedBox(width: 13),
                          Flexible(
                            fit: isMobile ? FlexFit.tight : FlexFit.loose,
                            child: SizedBox(
                            height: isMobile ? 48 : 36,
                            child: FilledButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      final trimmedReason = reason.text.trim();
                                      final trimmedCheckIn = checkIn.text.trim();
                                      final trimmedCheckOut = checkOut.text.trim();
                                      final needsCheckIn = type == 'missing_check_in' || type == 'incorrect_time';
                                      final needsCheckOut = type == 'missing_check_out' || type == 'incorrect_time';
                                      if (trimmedReason.length < 3) {
                                        setDialogState(() => errorMessage =
                                            'Enter a reason of at least 3 characters.');
                                        return;
                                      }
                                      if (needsCheckIn &&
                                          !RegExp(r'^\d{2}:\d{2}$')
                                              .hasMatch(trimmedCheckIn)) {
                                        setDialogState(() => errorMessage =
                                            'Enter the corrected check-in time as HH:MM.');
                                        return;
                                      }
                                      if (needsCheckOut && !RegExp(r'^\d{2}:\d{2}$').hasMatch(trimmedCheckOut)) {
                                        setDialogState(() => errorMessage = 'Enter the corrected check-out time as HH:MM.');
                                        return;
                                      }
                                      if (trimmedCheckIn.isNotEmpty && trimmedCheckOut.isNotEmpty && trimmedCheckOut.compareTo(trimmedCheckIn) <= 0) {
                                        setDialogState(() => errorMessage = 'Corrected check-out must be after check-in.');
                                        return;
                                      }

                                      setDialogState(() {
                                        isSubmitting = true;
                                        errorMessage = null;
                                      });
                                      try {
                                        final correctionLabel = {
                                              'incorrect_automatic_absence':
                                                  'Incorrect automatic absence',
                                              'missing_check_in':
                                                  'Missing check-in',
                                              'missing_check_out':
                                                  'Missing check-out',
                                              'incorrect_time': 'Incorrect time',
                                            }[type] ??
                                            'Other';
                                        final requestReason = [
                                          'Correction type: $correctionLabel',
                                          if (trimmedCheckIn.isNotEmpty)
                                            'Corrected check-in: $trimmedCheckIn',
                                          if (trimmedCheckOut.isNotEmpty)
                                            'Corrected check-out: $trimmedCheckOut',
                                          'Reason: $trimmedReason',
                                        ].join('\n');
                                        final token = _token;
                                        final response = await http
                                            .post(
                                              Uri.parse('${ApiConfig.baseUrl}/attendance/permissions'),
                                              headers: {
                                                'Content-Type': 'application/json',
                                                'Accept': 'application/json',
                                                if (token != null && token.isNotEmpty)
                                                  'Authorization': 'Bearer $token',
                                              },
                                              body: jsonEncode({
                                                'type':
                                                    'attendance_regularization',
                                                'date': DateFormat('yyyy-MM-dd')
                                                    .format(date),
                                                'correction_kind': type,
                                                if (trimmedCheckIn.isNotEmpty)
                                                  'corrected_check_in': trimmedCheckIn,
                                                if (trimmedCheckOut.isNotEmpty)
                                                  'corrected_check_out': trimmedCheckOut,
                                                'reason': requestReason,
                                              }),
                                            )
                                            .timeout(const Duration(seconds: 15));
                                        final body = jsonDecode(response.body);
                                        final message = body is Map
                                            ? body['message']?.toString()
                                            : null;
                                        if (response.statusCode >= 200 &&
                                            response.statusCode < 300 &&
                                            body is Map &&
                                            body['success'] == true) {
                                          if (!dialogContext.mounted) return;
                                          Navigator.pop(dialogContext);
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(this.context).showSnackBar(
                                            SnackBar(content: Text(message ?? 'Correction request submitted.')),
                                          );
                                          _fetchMonthData();
                                        } else {
                                          if (dialogContext.mounted) {
                                            setDialogState(() {
                                              errorMessage = message ??
                                                  'Unable to submit the correction request.';
                                              isSubmitting = false;
                                            });
                                          }
                                        }
                                      } catch (_) {
                                        if (dialogContext.mounted) {
                                          setDialogState(() {
                                            errorMessage =
                                                'Unable to submit the correction request. Please retry.';
                                            isSubmitting = false;
                                          });
                                        }
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0969F9),
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                textStyle: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(isMobile ? 'Submit for Approval' : 'Submit'),
                            ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          );
        },
      ),
      transitionBuilder: (_, animation, __, child) {
        if (!isMobile) {
          return FadeTransition(opacity: animation, child: child);
        }
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
    );
    reason.dispose();
    checkIn.dispose();
    checkOut.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calendar = _CalendarCard(
      year: year,
      month: month,
      label: monthLabel,
      onDayTap: (day) {
        setState(() => _selectedDate = DateTime(year, month, day));
        _showAttendanceDetails(day);
      },
      mobile: widget.mobile,
      dataFor: dataFor,
      onPrevious: () => changeMonth(-1),
      onNext: () => changeMonth(1),
    );

    final details = Column(children: [
      _SummaryCard(
        monthLabel: monthLabel,
        present: _presentCount,
        absent: _absentCount,
        late: _lateCount,
        workingDays: _workingDaysCount,
        premiumMobile: widget.mobile,
      ),
      const SizedBox(height: 16),
      _RecentAttendanceCard(
        month: monthNames[month - 1],
        session: _monthDays.isNotEmpty ? _monthDays.values.last : null,
        premiumMobile: widget.mobile,
      ),
    ]);

    final content = widget.mobile
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _PremiumAttendanceHeading(),
            const SizedBox(height: 16),
            calendar,
            const SizedBox(height: 16),
            _PremiumCorrectionBanner(
              monthLabel: monthLabel,
              onTap: _requestCorrection,
            ),
            const SizedBox(height: 16),
            details,
          ])
        : LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth < 980) {
            return Column(
                children: [calendar, const SizedBox(height: 18), details]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 7, child: calendar),
            const SizedBox(width: 20),
            Expanded(flex: 4, child: details),
          ]);
        });

    if (widget.mobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_loading) const LinearProgressIndicator(),
        content,
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_loading) const LinearProgressIndicator(),
      content,
    ]);
  }
}

class _AttendanceToast extends StatefulWidget {
  const _AttendanceToast({
    required this.title,
    required this.message,
    required this.onDismissed,
  });

  final String title;
  final String message;
  final VoidCallback onDismissed;

  @override
  State<_AttendanceToast> createState() => _AttendanceToastState();
}

class _AttendanceToastState extends State<_AttendanceToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _slide = Tween<Offset>(begin: const Offset(1.1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
    _dismissLater();
  }

  Future<void> _dismissLater() async {
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted || _dismissed) return;
    await _controller.reverse();
    if (mounted && !_dismissed) {
      _dismissed = true;
      widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SlideTransition(
            position: _slide,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 390,
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: const Color(0xFF26354F)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x420F172A), blurRadius: 22, offset: Offset(0, 10)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(color: employeeBlue, shape: BoxShape.circle),
                        child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.title, style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(widget.message, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: const Color(0xFFBFDBFE), fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          if (_dismissed) return;
                          _dismissed = true;
                          await _controller.reverse();
                          if (mounted) widget.onDismissed();
                        },
                        icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                        tooltip: 'Dismiss',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

}

class _PremiumAttendanceHeading extends StatelessWidget {
  const _PremiumAttendanceHeading();

  @override
  Widget build(BuildContext context) => Consumer<AuthService>(
        builder: (_, auth, __) {
          final staffId = '${auth.user?['staffId'] ?? auth.user?['employeeId'] ?? 'EMPLOYEE'}';
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attendance Calendar',
                      style: GoogleFonts.inter(
                        color: employeeNavy,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.45,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(staffId,
                        style: GoogleFonts.inter(color: employeeBlue, fontSize: 11, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text('Live Synced', style: GoogleFonts.inter(color: const Color(0xFF047857), fontSize: 10, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          );
        },
      );
}

class _PremiumCorrectionBanner extends StatelessWidget {
  const _PremiumCorrectionBanner({required this.monthLabel, required this.onTap});
  final String monthLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x260F172A), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: employeeBlue, shape: BoxShape.circle),
                  child: const Icon(Icons.edit_calendar_outlined, color: Colors.white, size: 21),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('Request Correction', style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(color: employeeBlue, borderRadius: BorderRadius.circular(5)),
                        child: Text('FAST-TRACK', style: GoogleFonts.inter(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                    const SizedBox(height: 3),
                    Text('Found punch discrepancy or missing log?', style: GoogleFonts.inter(color: const Color(0xFFCBD5E1), fontSize: 11)),
                  ]),
                ),
                TextButton(
                  onPressed: onTap,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: employeeNavy,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Apply', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, size: 15),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );

}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.year,
    required this.month,
    required this.label,
    required this.mobile,
    required this.dataFor,
    required this.onPrevious,
    required this.onNext,
    required this.onDayTap,
  });

  final int year;
  final int month;
  final String label;
  final bool mobile;
  final Map<String, dynamic> Function(int day) dataFor;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onDayTap;

  @override
  Widget build(BuildContext context) {
    final card = Column(children: [
          if (mobile)
            Container(
              height: 3,
              margin: const EdgeInsets.only(bottom: 13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [employeeBlue, Color(0xFF60A5FA), employeeBlue],
                ),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          Row(children: [
            _CalendarArrow(
                icon: Icons.chevron_left_rounded,
                onPressed: onPrevious,
                compact: mobile),
            Expanded(
              child: mobile
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.circle, size: 8, color: employeeBlue),
                        const SizedBox(width: 7),
                        Text.rich(
                          TextSpan(
                            text: '${label.split(' ').first} ',
                            style: GoogleFonts.inter(
                              color: employeeNavy,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                            children: [
                              TextSpan(
                                text: '$year',
                                style: const TextStyle(color: employeeBlue),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: employeeBlue,
                          fontSize: 25,
                          fontWeight: FontWeight.w800)),
            ),
            _CalendarArrow(
                icon: Icons.chevron_right_rounded,
                onPressed: onNext,
                compact: mobile),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1, color: employeeLine),
          const SizedBox(height: 8),
          _AttendanceCalendar(
              year: year, month: month, mobile: mobile, dataFor: dataFor, onDayTap: onDayTap),
          const SizedBox(height: 14),
          const Wrap(
              alignment: WrapAlignment.center,
              spacing: 15,
              runSpacing: 9,
              children: [
                _LegendStatus('P', 'Present', employeeBlue),
                _LegendStatus('A', 'Absent', Color(0xFFF2212F)),
                _LegendStatus('L', 'Late', employeeOrange),
                _LegendStatus('L', 'Leave', employeePurple),
                _LegendStatus('HL', 'Half Leave', employeePurple),
                _LegendStatus('OFF', 'Weekly Off', Color(0xFF7D8FAA)),
              ]),
        ]);
    if (!mobile) return EmployeeCard(padding: const EdgeInsets.all(22), child: card);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x100F172A), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: card,
    );
  }
}

class _AttendanceCalendar extends StatelessWidget {
  const _AttendanceCalendar({
    required this.year,
    required this.month,
    required this.mobile,
    required this.dataFor,
    required this.onDayTap,
  });

  final int year;
  final int month;
  final bool mobile;
  final Map<String, dynamic> Function(int day) dataFor;
  final ValueChanged<int> onDayTap;

  @override
  Widget build(BuildContext context) {
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final days = DateTime(year, month + 1, 0).day;
    final leading = DateTime(year, month, 1).weekday - 1;
    final used = leading + days;
    final trailing = (7 - used % 7) % 7;
    final cells = <Widget>[
      ...List.generate(leading, (_) => const _EmptyCalendarDay()),
      ...List.generate(days, (index) {
        final day = index + 1;
        final info = dataFor(day);
        return _CalendarDay(
          day: day,
          status: info['status']?.toString() ?? '',
          clockIn: info['clock_in']?.toString(),
          mobile: mobile,
          onTap: () => onDayTap(day),
        );
      }),
      ...List.generate(trailing, (_) => const _EmptyCalendarDay()),
    ];

    return Column(children: [
      Row(
        children: weekdays
            .asMap()
            .entries
            .map((entry) => Expanded(
                  child: SizedBox(
                    height: 34,
                    child: Center(
                      child: Text(entry.value,
                          style: TextStyle(
                              color: mobile && entry.key >= 5
                                  ? employeeBlue
                                  : (mobile ? employeeNavy : employeeMuted),
                              fontSize: mobile ? 10 : 11,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ))
            .toList(),
      ),
      ClipRRect(
        borderRadius: mobile ? BorderRadius.circular(16) : BorderRadius.zero,
        child: GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisExtent: mobile ? 60 : null,
          childAspectRatio: mobile ? 1 : 1.0,
          children: cells,
        ),
      ),
      if (mobile) ...[
        const SizedBox(height: 14),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

class _AttendanceDetailsSheet extends StatelessWidget {
  const _AttendanceDetailsSheet({
    required this.mobile,
    required this.date,
    required this.status,
    required this.statusLabel,
    required this.checkIn,
    required this.checkOut,
    required this.onClose,
  });

  final bool mobile;
  final DateTime date;
  final String status;
  final String statusLabel;
  final String checkIn;
  final String checkOut;
  final VoidCallback onClose;

  Color get _statusColor => switch (status) {
        'P' => const Color(0xFF059669),
        'L' => const Color(0xFFD97706),
        'A' => const Color(0xFFDC2626),
        'OFF' => const Color(0xFF64748B),
        'HL' || 'EL' || 'CL' || 'SL' || 'OL' => const Color(0xFF7C3AED),
        _ => employeeBlue,
      };

  Color get _statusSurface => switch (status) {
        'P' => const Color(0xFFECFDF5),
        'L' => const Color(0xFFFFF7ED),
        'A' => const Color(0xFFFEF2F2),
        'OFF' => const Color(0xFFF1F5F9),
        'HL' || 'EL' || 'CL' || 'SL' || 'OL' => const Color(0xFFF5F3FF),
        _ => const Color(0xFFEFF6FF),
      };

  @override
  Widget build(BuildContext context) {
    final body = Material(
      color: Colors.transparent,
      child: Container(
        width: mobile ? double.infinity : 430,
        padding: EdgeInsets.fromLTRB(24, mobile ? 10 : 22, 24, 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: const Radius.circular(26),
            bottom: Radius.circular(mobile ? 0 : 26),
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x330F172A), blurRadius: 30, offset: Offset(0, 14)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mobile)
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 17),
                  decoration: BoxDecoration(color: const Color(0xFFDCE5F1), borderRadius: BorderRadius.circular(99)),
                ),
              ),
            Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  border: Border.all(color: const Color(0xFFD6E7FF)),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.event_note_rounded, color: employeeBlue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Attendance details', style: GoogleFonts.inter(color: employeeNavy, fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text('Daily attendance record', style: GoogleFonts.inter(color: employeeMuted, fontSize: 11, fontWeight: FontWeight.w500)),
                ]),
              ),
              InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: employeeNavy, size: 21),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 17, color: employeeBlue),
                const SizedBox(width: 10),
                Expanded(child: Text(DateFormat('EEEE, d MMMM yyyy').format(date), style: GoogleFonts.inter(color: employeeNavy, fontSize: 13, fontWeight: FontWeight.w700))),
              ]),
            ),
            const SizedBox(height: 13),
            _AttendanceDetailsValue(
              label: 'Attendance status',
              value: statusLabel,
              leading: Icons.verified_rounded,
              valueColor: _statusColor,
              valueSurface: _statusSurface,
              pill: true,
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _AttendanceDetailsValue(
                  label: 'Check in',
                  value: checkIn,
                  leading: Icons.login_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AttendanceDetailsValue(
                  label: 'Check out',
                  value: checkOut,
                  leading: Icons.logout_rounded,
                ),
              ),
            ]),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: onClose,
                style: FilledButton.styleFrom(
                  backgroundColor: employeeBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                ),
                child: Text('Done', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
    if (mobile) return Align(alignment: Alignment.bottomCenter, child: body);
    return Center(child: body);
  }
}

class _AttendanceDetailsValue extends StatelessWidget {
  const _AttendanceDetailsValue({
    required this.label,
    required this.value,
    required this.leading,
    this.valueColor = employeeNavy,
    this.valueSurface = Colors.transparent,
    this.pill = false,
  });

  final String label;
  final String value;
  final IconData leading;
  final Color valueColor;
  final Color valueSurface;
  final bool pill;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(leading, size: 17, color: employeeBlue),
          const SizedBox(height: 9),
          Text(label, style: GoogleFonts.inter(color: employeeMuted, fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (pill)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: valueSurface, borderRadius: BorderRadius.circular(99)),
              child: Text(value, style: GoogleFonts.inter(color: valueColor, fontSize: 12, fontWeight: FontWeight.w800)),
            )
          else
            Text(value, style: GoogleFonts.inter(color: valueColor, fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
      );
}

class _EmptyCalendarDay extends StatelessWidget {
  const _EmptyCalendarDay();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: employeeLine, width: .7),
        ),
      );
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.day,
    required this.status,
    this.clockIn,
    this.mobile = false,
    this.onTap,
  });

  final int day;
  final String status;
  final String? clockIn;
  final bool mobile;
  final VoidCallback? onTap;

  Color get color => switch (status) {
        'A' => const Color(0xFFF2212F),
        'L' => employeeOrange,
        'H' => employeePurple,
        'LV' => employeePurple,
        'HL' => employeePurple,
        'OFF' => const Color(0xFF7D8FAA),
        _ => employeeBlue,
      };

  String? get formattedTime {
    if (clockIn == null || clockIn!.isEmpty) return null;
    try {
      // Force space format into strict ISO so Dart parse doesn't crash
      final safeClockIn = clockIn!.replaceFirst(' ', 'T');
      final dt = DateTime.parse(safeClockIn).toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return clockIn;
    }
  }

  String? get mobileTime {
    final time = formattedTime;
    if (time == null) return null;
    return time.replaceFirst(' ', '\n');
  }

  @override
  Widget build(BuildContext context) {
    final hasStatus = status.isNotEmpty;
    final timeStr = formattedTime;

    return InkWell(
      onTap: onTap,
      child: Container(
      decoration: BoxDecoration(
        color: status == 'OFF' ? const Color(0xFFF6F9FD) : Colors.white,
        border: Border.all(color: employeeLine, width: .7),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$day',
            style: TextStyle(
                color: employeeNavy,
                fontSize: mobile ? 13 : 13,
                fontWeight: FontWeight.w800),
          ),
          SizedBox(height: mobile ? 1 : 3),
          if (status == 'OFF')
            Text('OFF',
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w600))
          else if (hasStatus)
            Container(
              width: status == 'HL' ? (mobile ? 24 : 31) : (mobile ? 20 : 24),
              height: mobile ? 20 : 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text(
                status == 'LV' ? 'L' : status,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: mobile ? 9 : 10,
                    fontWeight: FontWeight.w800),
              ),
            ),
          if (timeStr != null) ...[
            SizedBox(height: mobile ? 1 : 3),
            Text(
              mobile ? mobileTime! : timeStr,
              textAlign: TextAlign.center,
              maxLines: mobile ? 2 : 1,
              style: TextStyle(
                fontSize: mobile ? 7 : 9,
                height: mobile ? .9 : null,
                fontWeight: FontWeight.w700,
                color: employeeNavy,
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

class _CalendarArrow extends StatelessWidget {
  const _CalendarArrow({
    required this.icon,
    required this.onPressed,
    this.compact = false,
  });
  final IconData icon;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: compact ? 34 : 42,
        height: compact ? 34 : 42,
        child: IconButton.outlined(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          icon: Icon(
            icon,
            color: compact ? employeeNavy : employeeBlue,
            size: compact ? 21 : 27,
          ),
          style: IconButton.styleFrom(
              backgroundColor:
                  compact ? const Color(0xFFF1F5F9) : Colors.transparent,
              side: BorderSide(
                  color: compact ? const Color(0xFFE2E8F0) : employeeLine),
              shape: compact
                  ? const CircleBorder()
                  : RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        ),
      );
}

class _LegendStatus extends StatelessWidget {
  const _LegendStatus(this.code, this.label, this.color);
  final String code;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: code == 'OFF' ? 34 : 27,
            height: 27,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: code == 'OFF' ? const Color(0xFFEAF0F8) : color,
              shape: code == 'OFF' ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: code == 'OFF' ? BorderRadius.circular(14) : null,
            ),
            child: Text(code,
                style: TextStyle(
                    color: code == 'OFF' ? employeeMuted : Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 7),
          Text(label,
              style: const TextStyle(color: employeeNavy, fontSize: 11)),
        ],
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.monthLabel,
    required this.present,
    required this.absent,
    required this.late,
    required this.workingDays,
    this.premiumMobile = false,
  });

  final String monthLabel;
  final int present;
  final int absent;
  final int late;
  final int workingDays;
  final bool premiumMobile;

  @override
  Widget build(BuildContext context) {
    final completed = present + late;
    final ratio = workingDays <= 0
        ? 0.0
        : (completed / workingDays).clamp(0.0, 1.0);
    // Stretch the children so the ratio track receives the card's full width.
    // With `start`, a `double.infinity` child can be laid out with a zero
    // intrinsic width inside this mobile card and the coloured segments vanish.
    final child = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${monthLabel.split(' ').first} Summary',
                  style: GoogleFonts.inter(
                      color: employeeNavy,
                      fontSize: premiumMobile ? 16 : 20,
                      fontWeight: FontWeight.w800)),
              if (premiumMobile)
                Text('Insights  →', style: GoogleFonts.inter(color: employeeBlue, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: premiumMobile
                ? BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(16),
                  )
                : null,
            child: Row(children: [
              Expanded(
                  child: _SummaryCell(
                      premiumMobile ? 'Working' : 'Working Days', '$workingDays', employeeBlue,
                      compact: premiumMobile)),
              Expanded(
                  child: _SummaryCell(
                      'Present', '$present', employeeBlue, compact: premiumMobile)),
              Expanded(
                  child: _SummaryCell(
                      'Absent', '$absent', const Color(0xFFF04438), compact: premiumMobile)),
              Expanded(
                  child: _SummaryCell(
                      'Late', '$late', employeeOrange, last: true, compact: premiumMobile)),
            ]),
          ),
          if (premiumMobile) ...[
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Attendance Ratio', style: GoogleFonts.inter(color: employeeNavy, fontSize: 11, fontWeight: FontWeight.w800)),
                Text('${(ratio * 100).toStringAsFixed(1)}% Completed', style: GoogleFonts.inter(color: employeeBlue, fontSize: 11, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 7),
            LayoutBuilder(builder: (context, constraints) {
              // Paint each segment at an explicit percentage.  This avoids the
              // flex children receiving a loose width when this card is inside
              // the mobile scroll view.
              final total = workingDays > 0 ? workingDays : 1;
              final presentWidth = constraints.maxWidth * present / total;
              final lateWidth = constraints.maxWidth * late / total;
              final absentWidth = constraints.maxWidth * absent / total;
              return Container(
                height: 8,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0F8),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Stack(children: [
                  if (presentWidth > 0)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: presentWidth,
                      child: const ColoredBox(color: employeeBlue),
                    ),
                  if (lateWidth > 0)
                    Positioned(
                      left: presentWidth,
                      top: 0,
                      bottom: 0,
                      width: lateWidth,
                      child: const ColoredBox(color: employeeOrange),
                    ),
                  if (absentWidth > 0)
                    Positioned(
                      left: presentWidth + lateWidth,
                      top: 0,
                      bottom: 0,
                      width: absentWidth,
                      child: const ColoredBox(color: Color(0xFFDC2626)),
                    ),
                ]),
              );
            }),
          ],
        ]);
    if (!premiumMobile) {
      return EmployeeCard(padding: const EdgeInsets.all(16), child: child);
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell(this.label, this.value, this.color, {this.last = false, this.compact = false});
  final String label;
  final String value;
  final Color color;
  final bool last;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(vertical: compact ? 10 : 12, horizontal: 3),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(right: BorderSide(color: employeeLine)),
        ),
        child: Column(children: [
          Text(label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: const TextStyle(color: employeeMuted, fontSize: 10)),
          SizedBox(height: compact ? 3 : 5),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: compact ? 20 : 25, fontWeight: FontWeight.w800)),
        ]),
      );
}

class _RecentAttendanceCard extends StatelessWidget {
  const _RecentAttendanceCard({required this.month, this.session, this.premiumMobile = false});
  final String month;
  final Map<String, dynamic>? session;
  final bool premiumMobile;

  @override
  Widget build(BuildContext context) {
    final hasSession = session != null && session!['clock_in'] != null;
    final status = hasSession ? (session!['status'] == 'L' ? 'Late' : 'Present') : 'None';
    final color = hasSession ? (session!['status'] == 'L' ? employeeOrange : employeeBlue) : employeeMuted;

    String timeStr = '—';
    if (hasSession && session!['clock_in'] != null) {
      try {
        final safeClockIn = session!['clock_in'].toString().replaceFirst(' ', 'T');
        timeStr = DateFormat('hh:mm a').format(DateTime.parse(safeClockIn).toLocal());
      } catch (_) {
        timeStr = session!['clock_in'];
      }
    }

    final child = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Recent Attendance',
              style: GoogleFonts.inter(
                  color: employeeNavy,
                  fontSize: premiumMobile ? 17 : 20,
                  fontWeight: FontWeight.w800)),
          if (premiumMobile)
            Text('Real-time',
                style: GoogleFonts.inter(
                    color: employeeMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
        ],
      ),
      const SizedBox(height: 10),
      if (premiumMobile)
        _PremiumRecentAttendanceRow(
          hasSession: hasSession,
          hasCheckedOut: hasSession && session!['clock_out'] != null,
          status: status,
          statusColor: color,
        )
      else
        _RecentAttendanceRow('Today', status, timeStr, color),
    ]);
    if (!premiumMobile) {
      return EmployeeCard(padding: const EdgeInsets.all(16), child: child);
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }
}

class _PremiumRecentAttendanceRow extends StatelessWidget {
  const _PremiumRecentAttendanceRow({
    required this.hasSession,
    required this.hasCheckedOut,
    required this.status,
    required this.statusColor,
  });

  final bool hasSession;
  final bool hasCheckedOut;
  final String status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final badgeText = hasCheckedOut ? status : 'Pending Punch';
    final badgeColor = hasCheckedOut ? statusColor : const Color(0xFF94A3B8);
    final date = DateFormat('d MMM yyyy').format(DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            border: Border.all(color: const Color(0xFFBFDBFE)),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.calendar_month_rounded, color: employeeBlue, size: 21),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Today', style: GoogleFonts.inter(color: employeeNavy, fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(width: 5),
              const Icon(Icons.circle, color: employeeOrange, size: 6),
            ]),
            const SizedBox(height: 3),
            Text('$date • General Shift',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(color: employeeMuted, fontSize: 10, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            border: Border.all(color: const Color(0xFFDCE5F1)),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, color: badgeColor, size: 6),
            const SizedBox(width: 5),
            Text(badgeText, style: GoogleFonts.inter(color: employeeNavy, fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }
}

class _RecentAttendanceRow extends StatelessWidget {
  const _RecentAttendanceRow(this.date, this.status, this.time, this.color);
  final String date;
  final String status;
  final String time;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.calendar_today_outlined,
                color: employeeBlue, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(date,
                  style: const TextStyle(
                      color: employeeNavy, fontWeight: FontWeight.w700))),
          CircleAvatar(radius: 4, backgroundColor: color),
          const SizedBox(width: 6),
          Text(status, style: TextStyle(color: color)),
          const SizedBox(width: 14),
          Text(time, style: const TextStyle(color: employeeMuted)),
        ]),
      );
}
