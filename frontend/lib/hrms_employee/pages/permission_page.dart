import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/api_config.dart';
import '../../services/auth_service.dart';
import '../shared/employee_ui.dart';

class EmployeePermissionPage extends StatelessWidget {
  const EmployeePermissionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final logOnly = ModalRoute.of(context)?.settings.arguments == 'log';
    return EmployeeScaffold(
      route: '/employee/permission',
      title: 'Permission',
      subtitle: logOnly
          ? 'Review your permission history'
          : 'Request short personal permission and review your history',
      desktop: _PermissionContent(logOnly: logOnly),
      mobile: _PermissionContent(mobile: true, logOnly: logOnly),
    );
  }
}

class _PermissionContent extends StatefulWidget {
  const _PermissionContent({this.mobile = false, this.logOnly = false});
  final bool mobile;
  final bool logOnly;

  @override
  State<_PermissionContent> createState() => _PermissionContentState();
}

class _PermissionContentState extends State<_PermissionContent> {
  final _reasonCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 14, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 16, minute: 0);

  bool _loading = false;
  bool _submitting = false;
  List<dynamic> _history = [];

  Widget _buildMobileRequest(BuildContext context) {
    InputDecoration input(String hint, IconData icon) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: employeeMuted, fontSize: 16),
      prefixIcon: Icon(icon, color: const Color(0xFF657493), size: 24),
      filled: true,
      fillColor: const Color(0xFFFCFDFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFE0E7F2), width: 1.4), borderRadius: BorderRadius.circular(16)),
      focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: employeeBlue, width: 1.5), borderRadius: BorderRadius.circular(16)),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const MobileEmployeeHeader(showGreeting: true),
      const SizedBox(height: 12),
      const Text('Permission', style: TextStyle(color: employeeNavy, fontSize: 36, fontWeight: FontWeight.w800)),
      const SizedBox(height: 32),
      Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF6B27EC), Color(0xFF0875EF)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(24)), child: Row(children: [
        Container(width: 72, height: 72, decoration: BoxDecoration(color: const Color(0x26FFFFFF), border: Border.all(color: const Color(0x55FFFFFF)), borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.verified_user_outlined, color: Colors.white, size: 42)),
        const SizedBox(width: 18),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Permission\nRequest', style: TextStyle(color: Colors.white, fontSize: 24, height: 1.12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text('Select your time away\nand send it for approval.', style: TextStyle(color: Color(0xD9FFFFFF), fontSize: 15, height: 1.35)),
          const SizedBox(height: 14),
          Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7), decoration: BoxDecoration(color: const Color(0x22FFFFFF), borderRadius: BorderRadius.circular(20)), child: const Text('MANAGER APPROVAL', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .45))),
        ])),
      ])),
      const SizedBox(height: 22),
      EmployeeCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Permission Date', style: TextStyle(color: employeeNavy, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        TextField(controller: _dateCtrl, readOnly: true, onTap: _pickDate, style: const TextStyle(color: employeeNavy, fontSize: 18, fontWeight: FontWeight.w700), decoration: input('Select date', Icons.calendar_today_outlined)),
        const SizedBox(height: 22),
        const Text('Time Away', style: TextStyle(color: employeeNavy, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        TextField(controller: _timeCtrl, readOnly: true, onTap: _pickTimeRange, style: const TextStyle(color: employeeNavy, fontSize: 18, fontWeight: FontWeight.w700), decoration: input('Select time', Icons.schedule_outlined)),
        const SizedBox(height: 22),
        const Text('Reason', style: TextStyle(color: employeeNavy, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        TextField(controller: _reasonCtrl, minLines: 4, maxLines: 4, style: const TextStyle(color: employeeNavy, fontSize: 16), decoration: input('Briefly describe the reason…', Icons.edit_outlined)),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 58, child: ElevatedButton.icon(onPressed: _submitting ? null : _submit, icon: _submitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_outlined, size: 27), label: Text(_submitting ? 'Submitting…' : 'Submit Request'), style: ElevatedButton.styleFrom(backgroundColor: employeeBlue, foregroundColor: Colors.white, elevation: 0, textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))),
      ])),
    ]);
  }
  @override
  void initState() {
    super.initState();
    _dateCtrl.text = DateFormat('dd/MM/yyyy').format(_selectedDate);
    _updateTimeText();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchHistory());
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  void _updateTimeText() {
    final startStr = _formatTimeOfDay(_startTime);
    final endStr = _formatTimeOfDay(_endTime);
    _timeCtrl.text = '$startStr – $endStr';
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    return DateFormat('hh:mm a').format(dt);
  }

  Future<void> _fetchHistory() async {
    final token = context.read<AuthService>().token;
    if (token == null) return;

    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/attendance/permissions/mine'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 12));
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true && mounted) {
        setState(() => _history = List<dynamic>.from(body['data'] as List? ?? []));
      }
    } catch (_) {
      // The page remains usable while the history request is unavailable.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime(2028),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  Future<void> _pickTimeRange() async {
    final pickedStart = await showTimePicker(
      context: context,
      initialTime: _startTime,
      helpText: 'SELECT START TIME',
    );
    if (pickedStart == null || !mounted) return;

    final pickedEnd = await showTimePicker(
      context: context,
      initialTime: _endTime,
      helpText: 'SELECT END TIME',
    );
    if (pickedEnd == null || !mounted) return;

    setState(() {
      _startTime = pickedStart;
      _endTime = pickedEnd;
      _updateTimeText();
    });
  }

  Future<void> _submit() async {
    final token = context.read<AuthService>().token;
    if (token == null) return;

    if (_reasonCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a reason for your permission.')),
      );
      return;
    }

    setState(() => _submitting = true);

    if (_startTime.hour == _endTime.hour && _startTime.minute == _endTime.minute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an end time later than the start time.')),
      );
      return;
    }

    final payload = {
      'type': 'permission',
      'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
      'start_time': '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
      'end_time': '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
      'reason': _reasonCtrl.text.trim(),
    };

    var ok = false;
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/attendance/permissions'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 12));
      ok = res.statusCode == 200 && (jsonDecode(res.body)['success'] == true);
    } catch (_) {}

    if (mounted) {
      setState(() => _submitting = false);
      if (ok) {
        _reasonCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission request submitted successfully!')),
        );
        _fetchHistory();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit permission request.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mobile && !widget.logOnly) return _buildMobileRequest(context);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.mobile) ...[
            const MobileEmployeeHeader(showGreeting: false),
            const SizedBox(height: 18),
            const Text('Permission',
                style: TextStyle(color: employeeNavy, fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
          ],
          if (!widget.logOnly) ...[
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pushNamed(
                  context,
                  '/employee/permission',
                  arguments: 'log',
                ),
                icon: const Icon(Icons.history_rounded, size: 18),
                label: const Text('View History'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!widget.logOnly)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: EmployeeCard(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6637E8), Color(0xFF3558D8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(color: Color(0x333558D8), blurRadius: 18, offset: Offset(0, 8)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0x33FFFFFF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0x55FFFFFF)),
                          ),
                          child: const Icon(Icons.verified_user_outlined, color: Colors.white, size: 27),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Permission request', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              const Text('Select your time away and send it for approval.', style: TextStyle(color: Color(0xD1FFFFFF), fontSize: 13)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                          decoration: BoxDecoration(color: const Color(0x2AFFFFFF), borderRadius: BorderRadius.circular(20)),
                          child: const Text('MANAGER APPROVAL', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .4)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  LayoutBuilder(builder: (context, constraints) {
                    final dateField = InkWell(
                      onTap: _pickDate,
                      child: IgnorePointer(
                        child: TextField(
                          controller: _dateCtrl,
                          decoration: const InputDecoration(labelText: 'Permission date', prefixIcon: Icon(Icons.calendar_today_outlined), border: OutlineInputBorder()),
                        ),
                      ),
                    );
                    final timeField = InkWell(
                      onTap: _pickTimeRange,
                      child: IgnorePointer(
                        child: TextField(
                          controller: _timeCtrl,
                          decoration: const InputDecoration(labelText: 'Time away', prefixIcon: Icon(Icons.schedule_outlined), border: OutlineInputBorder()),
                        ),
                      ),
                    );
                    if (constraints.maxWidth < 620) {
                      return Column(children: [dateField, const SizedBox(height: 14), timeField]);
                    }
                    return Row(children: [Expanded(child: dateField), const SizedBox(width: 14), Expanded(child: timeField)]);
                  }),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _reasonCtrl,
                    minLines: 3,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      hintText: 'Briefly describe your request...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_outlined, size: 16),
                      label: Text(_submitting ? 'Submitting…' : 'Submit Request'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B72F5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
                  ),
                ),
              ),
            ),
          if (widget.logOnly) ...[
            const SizedBox(height: 18),
            EmployeeCard(
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('Permission Log', subtitle: 'Past and pending permission requests'),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No permission requests recorded.', style: TextStyle(color: employeeMuted)),
                    ),
                  )
                else
                  ..._history.map((r) {
                    final status = r['status']?.toString() ?? 'Pending';
                    final salaryMode = r['salary_mode']?.toString().toLowerCase();
                    final normalizedStatus = status.toUpperCase();
                    final color = normalizedStatus == 'APPROVED'
                        ? employeeGreen
                        : (normalizedStatus == 'REJECTED' ? const Color(0xFFF12B46) : employeeOrange);
                    return _row(
                      _formatHistoryDate(r['date']?.toString() ?? ''),
                      r['reason']?.toString() ?? '',
                      '${_formatStoredTime(r['start_time']?.toString(), r['end_time']?.toString())}${salaryMode == 'paid' ? ' · With salary' : salaryMode == 'unpaid' ? ' · Without salary' : ''}',
                      status,
                      color,
                    );
                  }),
              ],
              ),
            ),
          ],
        ],
      );
  }

  String _formatHistoryDate(String value) {
    final date = DateTime.tryParse(value);
    return date == null ? value : DateFormat('dd/MM/yyyy').format(date);
  }

  String _formatStoredTime(String? start, String? end) {
    String format(String? value) {
      if (value == null || value.isEmpty) return '';
      final parts = value.split(':');
      if (parts.length < 2) return value;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) return value;
      return _formatTimeOfDay(TimeOfDay(hour: hour, minute: minute));
    }

    final from = format(start);
    final to = format(end);
    return from.isEmpty || to.isEmpty ? 'Time not recorded' : '$from – $to';
  }

  Widget _row(String date, String reason, String time, String status, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.shield_outlined, color: employeePurple),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(date, style: const TextStyle(color: employeeNavy, fontWeight: FontWeight.w700)),
                  Text('$reason · $time', style: const TextStyle(color: employeeMuted, fontSize: 12)),
                ],
              ),
            ),
            StatusPill(status, color),
          ],
        ),
      );
}
