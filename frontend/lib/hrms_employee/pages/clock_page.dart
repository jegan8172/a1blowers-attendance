import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/api_config.dart';
import '../../services/attendance_location.dart';
import '../../services/auth_service.dart';
import '../shared/employee_ui.dart';

class EmployeeClockPage extends StatelessWidget {
  const EmployeeClockPage({super.key});

  @override
  Widget build(BuildContext context) => const EmployeeScaffold(
        route: '/employee/clock-log',
        title: 'Clock In / Clock Out',
        subtitle: 'Track your daily working hours in real time',
        desktop: _ClockView(mobile: false),
        mobile: _ClockView(mobile: true),
      );
}

class _ClockView extends StatefulWidget {
  const _ClockView({required this.mobile}) : client = null;
  final bool mobile;
  final http.Client? client;

  @override
  State<_ClockView> createState() => _ClockViewState();
}

class _ClockViewState extends State<_ClockView> with WidgetsBindingObserver {
  late final http.Client _client;
  final _elapsed = Stopwatch();
  Timer? _timer;
  String? _token;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _punching = false;
  int _request = 0;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? http.Client();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_data?['status'] == 'checked_in') setState(() {});
      if (++_ticks % 60 == 0 && !_loading && !_punching) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = context.watch<AuthService>().token;
    if (_token != token || (_loading && _request == 0)) {
      _token = token;
      _data = null;
      _punching = false;
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_punching) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _client.close();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(
    String endpoint,
    String token, {
    bool post = false,
    Map<String, dynamic>? payload,
  }) async {
    // Use the configured backend for both validation and the attendance write.
    // Retrying a denied punch against an older server could bypass the rule.
    final url = Uri.parse('${ApiConfig.baseUrl}/attendance/$endpoint');
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final response = await (post
        ? _client.post(url, headers: headers, body: jsonEncode(payload ?? {}))
        : _client.get(url, headers: headers))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 401) {
      throw const _AttendanceError('Your session expired. Please sign in again.');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const _AttendanceError('Invalid response from server.');
    }

    if (response.statusCode != 200 || body['success'] != true) {
      throw _AttendanceError(
        body['message']?.toString() ?? 'Attendance request failed.',
      );
    }

    return Map<String, dynamic>.from(body['data'] as Map);
  }

  String _message(Object error) => error is _AttendanceError
      ? error.message
      : error is AttendanceLocationError
          ? error.message
          : 'Could not reach attendance. Check your connection and retry.';

  Future<void> _load() async {
    final token = _token;
    final request = ++_request;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _data = null;
        _error = 'Please sign in to view attendance.';
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await _call('dashboard', token);
      if (!mounted || request != _request || token != _token) return;
      setState(() {
        _data = data;
        _error = null;
        _elapsed
          ..reset()
          ..start();
      });
    } catch (error) {
      if (!mounted || request != _request || token != _token) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted && request == _request && token == _token) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _punch() async {
    final token = _token;
    if (token == null || _loading || _punching || _error != null) return;
    final clockOut = _data?['status'] == 'checked_in';
    String? reason;
    if (clockOut) {
      reason = await _clockOutReason();
      if (reason == null || !mounted) return;
    }
    setState(() => _punching = true);
    String message;
    try {
      final payload = clockOut ? <String, dynamic>{'reason': reason}
          : await AttendanceLocation.checkInPayload(client: _client, token: token);
      if (!mounted || token != _token) return;
      await _call(clockOut ? 'clock-out' : 'clock-in', token, post: true, payload: payload);
      message = clockOut ? 'You have been clocked out.' : 'You are now checked in.';
    } catch (error) {
      message = '${_message(error)} Refresh attendance before trying again.';
    }

    if (!mounted || token != _token) return;
    await _load();
    if (!mounted || token != _token) return;
    setState(() => _punching = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _clockOutReason() async {
    final controller = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Clock Out reason'),
          content: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 5,
            maxLength: 1000,
            decoration: InputDecoration(labelText: 'Reason', errorText: error, border: const OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              final value = controller.text.trim();
              if (value.length < 3) { setDialogState(() => error = 'Enter at least 3 characters.'); return; }
              Navigator.pop(dialogContext, value);
            }, child: const Text('Clock Out')),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  String _formatPunchTime(dynamic rawTimestamp) {
    if (rawTimestamp == null || rawTimestamp.toString().trim().isEmpty) {
      return '—:—';
    }
    try {
      final str = rawTimestamp.toString();
      DateTime dt;
      if (str.contains('T') || str.contains('-')) {
        dt = DateTime.parse(str).toLocal();
      } else {
        return str;
      }
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return rawTimestamp.toString();
    }
  }

  String _formatDuration(int totalSecs) {
    final h = (totalSecs ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSecs % 3600) ~/ 60).toString().padLeft(2, '0');
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final session = data?['session'] as Map?;
    final actions = data?['actions'] as Map? ?? {};
    final checkedIn = data?['status'] == 'checked_in';
    final checkedOut = data?['status'] == 'checked_out';

    final seconds = (session?['worked_seconds'] as num?)?.toInt() ?? 0;
    final workedSeconds = seconds + (checkedIn ? _elapsed.elapsed.inSeconds : 0);
    final extraSeconds = workedSeconds > 28800 ? workedSeconds - 28800 : 0;

    final punchInDisplay = _formatPunchTime(
      session?['punch_in'] ?? session?['clock_in'] ?? session?['clock_in_at'],
    );
    final punchOutDisplay = _formatPunchTime(
      session?['punch_out'] ?? session?['clock_out'] ?? session?['clock_out_at'],
    );

    final todayFormatted = DateFormat('dd MMM yyyy').format(DateTime.now()).toUpperCase();
    final recentRecords = ((data?['month_records'] as List?) ?? const [])
        .whereType<Map>()
        .map((record) => Map<String, dynamic>.from(record))
        .toList()
      ..sort((left, right) => (right['work_date']?.toString() ?? '')
          .compareTo(left['work_date']?.toString() ?? ''));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(child: Text('Attendance error: $_error', style: const TextStyle(color: Colors.red))),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        EmployeeCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(builder: (context, constraints) {
                final isWide = constraints.maxWidth > 700;
                final metrics = [
                  _SessionMetric(
                    title: "TODAY'S SESSION — $todayFormatted",
                    value: punchInDisplay,
                    caption: checkedIn
                        ? 'Clock In'
                        : (checkedOut ? 'Ended at $punchOutDisplay' : 'Not clocked in'),
                  ),
                  _SessionMetric(
                    title: 'ELAPSED TODAY',
                    value: _formatDuration(workedSeconds),
                    caption: checkedIn ? 'Still checked in' : 'Session closed',
                    valueColor: employeeBlue,
                  ),
                  _SessionMetric(
                    title: 'EXTRA HOURS (BEYOND 8H SHIFT)',
                    value: _formatDuration(extraSeconds),
                    caption: '⚠ Not compensated',
                    valueColor: extraSeconds > 0 ? employeeOrange : employeeNavy,
                    captionColor: employeeOrange,
                  ),
                ];

                final actionButton = ElevatedButton.icon(
                  onPressed: _loading ||
                          _punching ||
                          !(actions['can_clock_in'] == true || actions['can_clock_out'] == true)
                      ? null
                      : _punch,
                  icon: _punching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Icon(checkedIn ? Icons.logout : Icons.login, size: 18),
                  label: Text(_punching
                      ? 'Saving…'
                      : checkedIn
                          ? 'Clock Out'
                          : checkedOut
                              ? 'Completed'
                              : 'Clock In'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: checkedIn ? const Color(0xFF0668F5) : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: metrics[0]),
                      Expanded(child: metrics[1]),
                      Expanded(child: metrics[2]),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          actionButton,
                          const SizedBox(height: 6),
                          const Text(
                            'Standard shift: 09:00 AM - 05:00 PM',
                            style: TextStyle(color: employeeMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      metrics[0],
                      const SizedBox(height: 14),
                      metrics[1],
                      const SizedBox(height: 14),
                      metrics[2],
                      const SizedBox(height: 18),
                      actionButton,
                    ],
                  );
                }
              }),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8EE),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFECC8)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: employeeOrange, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Policy: Extra hours beyond the 8-hour shift are recorded on your attendance log for visibility only. They do not add to salary or generate compensation.',
                        style: TextStyle(color: employeeNavy, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _RecentClockRecords(records: recentRecords.take(5).toList()),
      ],
    );
  }
}

class _RecentClockRecords extends StatelessWidget {
  const _RecentClockRecords({required this.records});

  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) => EmployeeCard(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.history_rounded, color: employeeBlue, size: 22),
            SizedBox(width: 9),
            Text('Recent Clock Records', style: TextStyle(color: employeeNavy, fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          const Text('Your latest check-in and check-out sessions', style: TextStyle(color: employeeMuted, fontSize: 12)),
          const SizedBox(height: 14),
          if (records.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 26), child: Center(child: Text('No clock records yet.', style: TextStyle(color: employeeMuted))))
          else
            LayoutBuilder(builder: (context, constraints) {
              final compact = constraints.maxWidth < 650;
              return Column(children: [
                if (!compact) const _RecentRecordHeader(),
                ...records.map((record) => _RecentRecordRow(record: record, compact: compact)),
              ]);
            }),
        ]),
      );
}

class _RecentRecordHeader extends StatelessWidget {
  const _RecentRecordHeader();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 7),
        child: Row(children: [
          Expanded(flex: 3, child: Text('DATE', style: _recordHeaderStyle)),
          Expanded(flex: 2, child: Text('CHECK IN', style: _recordHeaderStyle)),
          Expanded(flex: 2, child: Text('CHECK OUT', style: _recordHeaderStyle)),
          Expanded(flex: 2, child: Text('WORKED', style: _recordHeaderStyle)),
          Expanded(flex: 2, child: Text('STATUS', style: _recordHeaderStyle)),
        ]),
      );
}

const _recordHeaderStyle = TextStyle(color: employeeMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .5);

class _RecentRecordRow extends StatelessWidget {
  const _RecentRecordRow({required this.record, required this.compact});

  final Map<String, dynamic> record;
  final bool compact;

  DateTime? _timestamp(dynamic value) => value == null ? null : DateTime.tryParse(value.toString().replaceFirst(' ', 'T'))?.toLocal();

  String _dateLabel() {
    final raw = record['work_date']?.toString() ?? '';
    final value = raw.length >= 10 ? raw.substring(0, 10) : raw;
    final date = DateTime.tryParse(value);
    return date == null ? '—' : DateFormat('EEE, dd MMM').format(date);
  }

  String _timeLabel(dynamic value) {
    final date = _timestamp(value);
    return date == null ? '—' : DateFormat('hh:mm a').format(date);
  }

  String _duration() {
    final start = _timestamp(record['clock_in_at']);
    final end = _timestamp(record['clock_out_at']);
    if (start == null) return '—';
    if (end == null) return 'In progress';
    final minutes = end.difference(start).inMinutes.clamp(0, 1440);
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final late = record['is_late'] == true || record['is_late'] == 1;
    final active = record['clock_out_at'] == null;
    final status = late ? 'Late' : active ? 'Active' : 'Present';
    final color = late ? employeeOrange : active ? employeeBlue : const Color(0xFF0AA85A);
    final background = late ? const Color(0xFFFFF3E9) : active ? const Color(0xFFEAF2FF) : const Color(0xFFEAF8F0);
    final statusChip = Align(alignment: Alignment.centerLeft, child: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(99)), child: Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700))));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFFFBFCFF), border: Border.all(color: const Color(0xFFE5EBF5)), borderRadius: BorderRadius.circular(8)),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_value(_dateLabel(), bold: true), statusChip]),
              const SizedBox(height: 10),
              Row(children: [Expanded(child: _compactValue('Check in', _timeLabel(record['clock_in_at']))), Expanded(child: _compactValue('Check out', _timeLabel(record['clock_out_at']))), Expanded(child: _compactValue('Worked', _duration()))]),
            ])
          : Row(children: [
              Expanded(flex: 3, child: _value(_dateLabel(), bold: true)),
              Expanded(flex: 2, child: _value(_timeLabel(record['clock_in_at']))),
              Expanded(flex: 2, child: _value(_timeLabel(record['clock_out_at']))),
              Expanded(flex: 2, child: _value(_duration())),
              Expanded(flex: 2, child: statusChip),
            ]),
    );
  }

  Widget _value(String value, {bool bold = false}) => Text(value, style: TextStyle(color: employeeNavy, fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500));
  Widget _compactValue(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: _recordHeaderStyle), const SizedBox(height: 3), _value(value)]);
}

class _SessionMetric extends StatelessWidget {
  const _SessionMetric({
    required this.title,
    required this.value,
    required this.caption,
    this.valueColor = employeeNavy,
    this.captionColor = employeeMuted,
  });

  final String title;
  final String value;
  final String caption;
  final Color valueColor;
  final Color captionColor;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: employeeMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: valueColor, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(caption,
              style: TextStyle(
                  color: captionColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      );
}
class _AttendanceError implements Exception {
  const _AttendanceError(this.message);
  final String message;
}


