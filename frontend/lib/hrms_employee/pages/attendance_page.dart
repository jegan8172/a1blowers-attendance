import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/api_config.dart';
import '../../services/auth_service.dart';
import '../shared/employee_ui.dart';

class EmployeeAttendancePage extends StatelessWidget {
  const EmployeeAttendancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthName = DateFormat('MMMM yyyy').format(now);

    return EmployeeScaffold(
      route: '/employee/attendance',
      title: 'Attendance Calendar',
      subtitle: 'Your attendance for $monthName',
      desktop: const _AttendanceView(mobile: false),
      mobile: const _AttendanceView(mobile: true),
    );
  }
}

class _AttendanceView extends StatefulWidget {
  const _AttendanceView({required this.mobile});
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

  @override
  Widget build(BuildContext context) {
    final calendar = _CalendarCard(
      year: year,
      month: month,
      label: monthLabel,
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

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_loading) const LinearProgressIndicator(),
      if (widget.mobile) ...[
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
      ] else
        LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth < 980) {
            return Column(
                children: [calendar, const SizedBox(height: 18), details]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 7, child: calendar),
            const SizedBox(width: 20),
            Expanded(flex: 4, child: details),
          ]);
        }),
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
  });

  final int year;
  final int month;
  final String label;
  final bool mobile;
  final Map<String, dynamic> Function(int day) dataFor;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

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
              year: year, month: month, mobile: mobile, dataFor: dataFor),
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
  });

  final int year;
  final int month;
  final bool mobile;
  final Map<String, dynamic> Function(int day) dataFor;

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
  });

  final int day;
  final String status;
  final String? clockIn;

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

    return Container(
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
