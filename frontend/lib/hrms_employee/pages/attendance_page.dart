import 'dart:convert';

import 'package:flutter/material.dart';
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
    _fetchMonthData();
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
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.calendar_month_outlined, color: employeeBlue),
            const SizedBox(width: 10),
            const Expanded(child: Text('Attendance details')),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE, d MMMM yyyy').format(selected),
                style: const TextStyle(
                  color: employeeNavy,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              _AttendanceDetailLine(
                label: 'Status',
                value: _statusLabel(status),
              ),
              _AttendanceDetailLine(
                label: 'Check in',
                value: _formatClock(info['clock_in']),
              ),
              _AttendanceDetailLine(
                label: 'Check out',
                value: _formatClock(info['clock_out']),
              ),
            ],
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

  Future<void> _requestCorrection() async {
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
    String type = 'incorrect_automatic_absence';
    bool isSubmitting = false;
    String? errorMessage;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          const borderColor = Color(0xFFD6E1F4);
          const surfaceColor = Color(0xFFF6F8FC);
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

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.edit_calendar_outlined,
                            color: Color(0xFF0969F9), size: 24),
                        SizedBox(width: 10),
                        Text('Request Correction',
                            style: TextStyle(
                                color: Color(0xFF0C1C49),
                                fontSize: 22,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 30),
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
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Attendance date',
                                    style: TextStyle(
                                        color: Color(0xFF66789B), fontSize: 13)),
                                const SizedBox(height: 3),
                                Text(DateFormat('dd MMM yyyy').format(date),
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
                    const SizedBox(height: 22),
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
                          DropdownMenuItem(value: 'other', child: Text('Other')),
                        ],
                        onChanged: isSubmitting
                            ? null
                            : (value) => setDialogState(() => type = value!),
                      ),
                    ),
                    const SizedBox(height: 13),
                    SizedBox(
                      height: 56,
                      child: TextField(
                        controller: checkIn,
                        enabled: !isSubmitting,
                        keyboardType: TextInputType.datetime,
                        style: const TextStyle(fontSize: 16),
                        decoration: fieldDecoration.copyWith(
                          hintText: 'Correct check-in time (HH:MM)',
                          hintStyle: const TextStyle(
                              color: Color(0xFF667089), fontSize: 16),
                          suffixIcon: const Icon(Icons.schedule_outlined,
                              color: Color(0xFF0969F9), size: 23),
                        ),
                      ),
                    ),
                    const SizedBox(height: 13),
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
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
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
                          const SizedBox(width: 13),
                          SizedBox(
                            height: 36,
                            child: FilledButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      final trimmedReason = reason.text.trim();
                                      final trimmedCheckIn = checkIn.text.trim();
                                      final needsCheckIn = type == 'missing_check_in' ||
                                          type == 'incorrect_check_in_time';
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
                                              'other': 'Other',
                                            }[type] ??
                                            'Other';
                                        final requestReason = [
                                          'Correction type: $correctionLabel',
                                          if (trimmedCheckIn.isNotEmpty)
                                            'Corrected check-in: $trimmedCheckIn',
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
                                  : const Text('Submit'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    reason.dispose();
    checkIn.dispose();
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
      ),
      const SizedBox(height: 16),
      _RecentAttendanceCard(
        month: monthNames[month - 1],
        session: _monthDays.isNotEmpty ? _monthDays.values.last : null,
      ),
    ]);

    final content = widget.mobile
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const MobileEmployeeHeader(showGreeting: false),
        const SizedBox(height: 24),
        const Text('Attendance Calendar',
            style: TextStyle(
                color: employeeNavy,
                fontSize: 28,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text('Your attendance for $monthLabel',
            style: const TextStyle(color: employeeMuted, fontSize: 16)),
        const SizedBox(height: 18),
        calendar,
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
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _requestCorrection,
            style: FilledButton.styleFrom(
              backgroundColor: employeeBlue,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.edit_calendar_outlined),
            label: const Text('Request Correction'),
          ),
        ),
        const SizedBox(height: 12),
        content,
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_loading) const LinearProgressIndicator(),
      content,
    ]);
  }
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
  Widget build(BuildContext context) => EmployeeCard(
        padding: EdgeInsets.all(mobile ? 14 : 22),
        child: Column(children: [
          Row(children: [
            _CalendarArrow(
                icon: Icons.chevron_left_rounded, onPressed: onPrevious),
            Expanded(
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: employeeBlue,
                      fontSize: mobile ? 22 : 25,
                      fontWeight: FontWeight.w800)),
            ),
            _CalendarArrow(
                icon: Icons.chevron_right_rounded, onPressed: onNext),
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
        ]),
      );
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
          onTap: () => onDayTap(day),
        );
      }),
      ...List.generate(trailing, (_) => const _EmptyCalendarDay()),
    ];

    return Column(children: [
      Row(
        children: weekdays
            .map((day) => Expanded(
                  child: SizedBox(
                    height: 34,
                    child: Center(
                      child: Text(day,
                          style: TextStyle(
                              color: employeeMuted,
                              fontSize: mobile ? 9 : 11,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ))
            .toList(),
      ),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: mobile ? .65 : 1.0,
        children: cells,
      ),
    ]);
  }
}

class _AttendanceDetailLine extends StatelessWidget {
  const _AttendanceDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F9FD),
      border: Border.all(color: employeeLine),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Text(label, style: const TextStyle(color: employeeMuted)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: employeeNavy,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
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
    this.onTap,
  });

  final int day;
  final String status;
  final String? clockIn;
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
            style: const TextStyle(
                color: employeeNavy, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          if (status == 'OFF')
            Text('OFF',
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w600))
          else if (hasStatus)
            Container(
              width: status == 'HL' ? 31 : 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text(
                status == 'LV' ? 'L' : status,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800),
              ),
            ),
          if (timeStr != null) ...[
            const SizedBox(height: 3),
            Text(
              timeStr,
              style: const TextStyle(
                fontSize: 9,
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
  const _CalendarArrow({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 42,
        height: 42,
        child: IconButton.outlined(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          icon: Icon(icon, color: employeeBlue, size: 27),
          style: IconButton.styleFrom(
              side: const BorderSide(color: employeeLine),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
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
  });

  final String monthLabel;
  final int present;
  final int absent;
  final int late;
  final int workingDays;

  @override
  Widget build(BuildContext context) => EmployeeCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${monthLabel.split(' ').first} Summary',
              style: const TextStyle(
                  color: employeeBlue,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: _SummaryCell(
                    'Working Days', '$workingDays', employeeBlue)),
            Expanded(
                child: _SummaryCell(
                    'Present', '$present', employeeBlue)),
            Expanded(
                child: _SummaryCell(
                    'Absent', '$absent', const Color(0xFFF04438))),
            Expanded(
                child: _SummaryCell(
                    'Late', '$late', employeeOrange, last: true)),
          ]),
        ]),
      );
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell(this.label, this.value, this.color, {this.last = false});
  final String label;
  final String value;
  final Color color;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 3),
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
          const SizedBox(height: 5),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 25, fontWeight: FontWeight.w800)),
        ]),
      );
}

class _RecentAttendanceCard extends StatelessWidget {
  const _RecentAttendanceCard({required this.month, this.session});
  final String month;
  final Map<String, dynamic>? session;

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

    return EmployeeCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Recent Attendance',
            style: TextStyle(
                color: employeeBlue,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        _RecentAttendanceRow('Today', status, timeStr, color),
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
