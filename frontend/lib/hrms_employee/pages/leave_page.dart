import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/api_config.dart';
import '../../services/auth_service.dart';
import '../shared/employee_ui.dart';

List<String> _attendanceBaseUrls() {
  return ['${ApiConfig.baseUrl}/attendance'];
}

// A visible card can be usage-only (for example, a zero-balance Sick Leave
// card).  That card is informative, but it must not become an invalid option
// in the application form.
List<Map<String, dynamic>> _applicableLeavePolicies(List<dynamic> balances) => balances
    .where((balance) {
      if (balance is! Map) return false;
      final canApply = balance['canApply'];
      if (canApply is bool) return canApply;
      if (canApply is num) return canApply != 0;
      return (balance['total'] as num? ?? 0) > 0;
    })
    .map((balance) => Map<String, dynamic>.from(balance))
    .toList();

class EmployeeLeavePage extends StatefulWidget {
  const EmployeeLeavePage({super.key});

  @override
  State<EmployeeLeavePage> createState() => _EmployeeLeavePageState();
}

class _EmployeeLeavePageState extends State<EmployeeLeavePage> {
  bool _loading = true;
  List<dynamic> _balances = [];
  List<dynamic> _requests = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchLeaveData());
  }

  List<String> _getBaseUrls() {
    return _attendanceBaseUrls();
  }

  Future<void> _fetchLeaveData() async {
    final token = context.read<AuthService>().token;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Your session is unavailable. Please sign in again.';
        });
      }
      return;
    }

    setState(() => _loading = true);

    for (final base in _getBaseUrls()) {
      try {
        final url = Uri.parse('$base/leave/dashboard');
        final res = await http
            .get(
              url,
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          if (body['success'] == true && body['data'] != null) {
            if (mounted) {
              setState(() {
                _balances = body['data']['balances'] ?? [];
                _requests = body['data']['requests'] ?? [];
                _loading = false;
                _error = null;
              });
            }
            return;
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _loading = false;
        _error = 'Unable to reach leave server.';
      });
    }
  }

  Future<void> _cancelLeave(dynamic leaveId) async {
    final token = context.read<AuthService>().token;
    if (token == null) return;

    for (final base in _getBaseUrls()) {
      try {
        final url = Uri.parse('$base/leave/cancel');
        final res = await http.post(
          url,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'leave_id': leaveId}),
        );
        if (res.statusCode == 200) {
          _fetchLeaveData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Leave request cancelled.')),
            );
          }
          return;
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode =
        ModalRoute.of(context)?.settings.arguments as String? ?? 'apply';

    return EmployeeScaffold(
      route: '/employee/leave',
      title: 'Leave',
      subtitle: '',
      desktop: _DesktopLeave(
        mode: mode,
        loading: _loading,
        error: _error,
        balances: _balances,
        requests: _requests,
        onRefresh: _fetchLeaveData,
        onCancel: _cancelLeave,
      ),
      mobile: _MobileLeave(
        mode: mode,
        loading: _loading,
        error: _error,
        balances: _balances,
        requests: _requests,
        onRefresh: _fetchLeaveData,
        onCancel: _cancelLeave,
      ),
    );
  }
}

class _DesktopLeave extends StatelessWidget {
  const _DesktopLeave({
    required this.mode,
    required this.loading,
    required this.error,
    required this.balances,
    required this.requests,
    required this.onRefresh,
    required this.onCancel,
  });

  final String mode;
  final bool loading;
  final String? error;
  final List<dynamic> balances;
  final List<dynamic> requests;
  final VoidCallback onRefresh;
  final ValueChanged<dynamic> onCancel;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return _LeaveLoadError(message: error!, onRetry: onRefresh);
    }

    if (mode == 'requests') {
      return _RequestList(requests: requests, onCancel: onCancel);
    }

    return Column(
      children: [
        _LeaveBalance(balances: balances),
        const SizedBox(height: 20),
        _LeaveForm(desktop: true, leavePolicies: _applicableLeavePolicies(balances), onSuccess: onRefresh),
      ],
    );
  }
}

class _LeaveBalance extends StatelessWidget {
  const _LeaveBalance({required this.balances});
  final List<dynamic> balances;

  Color _colorFor(String type) {
    switch (type) {
      case 'Casual Leave':
        return employeeGreen;
      case 'Sick Leave':
        return employeePurple;
      case 'Earned Leave':
        return employeeBlue;
      default:
        return employeeOrange;
    }
  }

  @override
  Widget build(BuildContext context) => EmployeeCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (balances.isEmpty)
          const Text(
            'No balance data available',
            style: TextStyle(color: employeeMuted),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final boxWidth = constraints.maxWidth >= 900
                  ? (constraints.maxWidth - 48) / 4
                  : constraints.maxWidth >= 560
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;
              return Wrap(
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: balances.map((b) {
                  final total = (b['total'] as num?) ?? 0;
                  final used = (b['used'] as num?) ?? 0;
                  final type = b['type']?.toString() ?? 'Leave';
                  return SizedBox(
                    width: boxWidth,
                    child: _BalanceBox(
                      label: b['isPaidLeave'] == true ? '$type (Paid)' : type,
                      remaining: (total - used).clamp(0, total),
                      total: total,
                      color: _colorFor(type),
                    ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    ),
  );
}

class _LeaveLoadError extends StatelessWidget {
  const _LeaveLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmployeeCard(
    child: Row(
      children: [
        const Icon(Icons.cloud_off_outlined, color: employeeOrange),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message, style: const TextStyle(color: employeeMuted)),
        ),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _BalanceBox extends StatelessWidget {
  const _BalanceBox({
    required this.label,
    required this.remaining,
    required this.total,
    required this.color,
  });

  final String label;
  final num remaining;
  final num total;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: 126,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      border: Border.all(color: color.withValues(alpha: 0.22)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const Spacer(),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: employeeMuted),
        ),
        const SizedBox(height: 4),
        Text(
          '${_days(remaining)} / ${_days(total)} days',
          style: TextStyle(
            color: color,
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

String _days(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

class _RequestList extends StatelessWidget {
  const _RequestList({required this.requests, required this.onCancel});
  final List<dynamic> requests;
  final ValueChanged<dynamic> onCancel;

  @override
  Widget build(BuildContext context) => EmployeeCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          'My Requests',
          subtitle: 'Recent and pending leave requests',
        ),
        const SizedBox(height: 14),
        if (requests.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No leave requests found.',
                style: TextStyle(color: employeeMuted),
              ),
            ),
          )
        else
          ...requests.map((r) => _DesktopRequestRow(r: r, onCancel: onCancel)),
      ],
    ),
  );
}

class _DesktopRequestRow extends StatelessWidget {
  const _DesktopRequestRow({required this.r, required this.onCancel});
  final dynamic r;
  final ValueChanged<dynamic> onCancel;

  Color _statusColor(String status) {
    switch (status) {
      case 'APPROVED':
        return const Color(0xFF14863C);
      case 'DENIED':
      case 'CANCELLED':
        return const Color(0xFFF12B46);
      default:
        return employeeOrange;
    }
  }

  @override
  Widget build(BuildContext context) {
    DateTime? fromDt;
    try {
      fromDt = DateTime.parse(r['from_date'].toString());
    } catch (_) {}

    final dayStr = fromDt != null ? DateFormat('dd').format(fromDt) : '--';
    final monthStr = fromDt != null
        ? DateFormat('MMM').format(fromDt).toUpperCase()
        : '---';
    final status = r['status']?.toString() ?? 'PENDING';
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: employeeLine)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F6FB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  dayStr,
                  style: const TextStyle(
                    color: employeeNavy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  monthStr,
                  style: const TextStyle(color: employeeMuted, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r['leave_type']} · ${r['duration_type'] ?? 'Full Day'}',
                  style: const TextStyle(
                    color: employeeNavy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${r['reason'] ?? 'No reason provided'} · ${r['from_date']} to ${r['to_date']}',
                  style: const TextStyle(color: employeeMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          StatusPill(status, color),
          if (status == 'PENDING') ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(
                Icons.close_rounded,
                color: Color(0xFFF12B46),
                size: 18,
              ),
              tooltip: 'Cancel Request',
              onPressed: () => onCancel(r['id']),
            ),
          ],
        ],
      ),
    );
  }
}

class _LeaveForm extends StatefulWidget {
  const _LeaveForm({required this.desktop, required this.leavePolicies, required this.onSuccess});
  final bool desktop;
  final List<Map<String, dynamic>> leavePolicies;
  final VoidCallback onSuccess;

  @override
  State<_LeaveForm> createState() => _LeaveFormState();
}

class _LeaveFormState extends State<_LeaveForm> {
  String type = 'Casual Leave';
  String duration = 'Full Day';
  String halfDaySession = 'morning';
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.leavePolicies.isNotEmpty && !widget.leavePolicies.any((item) => '${item['type']}' == type)) type = '${widget.leavePolicies.first['type']}';
  }

  @override
  void didUpdateWidget(covariant _LeaveForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.leavePolicies.isNotEmpty && !widget.leavePolicies.any((item) => '${item['type']}' == type)) {
      setState(() => type = '${widget.leavePolicies.first['type']}');
    }
  }

  bool get _allowsHalfDay {
    final policy = widget.leavePolicies.where((item) => '${item['type']}' == type).toList();
    if (policy.isEmpty) return false;
    final value = policy.first['allowsHalfDay'];
    return value == true || value == 1;
  }

  Future<void> _pickDate(bool isFrom) async {
    final initial = isFrom ? fromDate : toDate;
    final picked = widget.desktop
        ? await showDatePicker(
            context: context,
            initialDate: initial,
            firstDate: DateTime(2025),
            lastDate: DateTime(2028),
          )
        : await _showCompactLeaveCalendar(initial);
    if (picked != null) {
      setState(() {
        if (isFrom) {
          fromDate = picked;
          if (toDate.isBefore(fromDate)) toDate = fromDate;
        } else {
          toDate = picked;
        }
      });
    }
  }

  Future<DateTime?> _showCompactLeaveCalendar(DateTime initial) => showDialog<DateTime>(
    context: context,
    barrierColor: const Color(0x660F172A),
    builder: (_) => _CompactLeaveCalendar(initialDate: initial),
  );

  Future<void> _submit() async {
    final token = context.read<AuthService>().token;
    if (token == null) return;

    if (_reasonCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a reason for leave.')),
      );
      return;
    }

    setState(() => _submitting = true);

    final payload = {
      'leave_type': type,
      'duration_type': duration,
      if (duration == 'Half Day') 'half_day_session': halfDaySession,
      'from_date': DateFormat('yyyy-MM-dd').format(fromDate),
      'to_date': DateFormat('yyyy-MM-dd').format(toDate),
      'reason': _reasonCtrl.text.trim(),
    };

    final candidateUrls = _attendanceBaseUrls()
        .map((base) => '$base/leave/apply')
        .toList();

    bool ok = false;
    String? submitError;
    for (final base in candidateUrls) {
      try {
        final res = await http.post(
          Uri.parse(base),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        );
        final body = jsonDecode(res.body);
        if (res.statusCode == 200 && body is Map && body['success'] != false) {
          ok = true;
          break;
        }
        if (body is Map && body['message'] != null) {
          submitError = body['message'].toString();
          break;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() => _submitting = false);
      if (ok) {
        _reasonCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Leave application submitted successfully!'),
          ),
        );
        widget.onSuccess();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(submitError ?? 'Failed to submit leave. Check connection.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fromStr = DateFormat('dd/MM/yyyy').format(fromDate);
    final toStr = DateFormat('dd/MM/yyyy').format(toDate);

    if (widget.leavePolicies.isEmpty) {
      return const EmployeeCard(child: Text('No leave types are currently available. Please contact your administrator.'));
    }

    if (!widget.desktop) return _premiumMobileForm(context, fromStr, toStr);

    return EmployeeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            'Apply for Leave',
            subtitle: 'Submit a new leave request for manager approval',
          ),
          const SizedBox(height: 18),
          if (widget.desktop)
            Row(
              children: [
                Expanded(
                  child: _DropdownField('LEAVE TYPE', type, widget.leavePolicies.map((item) => '${item['type']}').toList(), (v) => setState(() { type = v!; if (!_allowsHalfDay && duration == 'Half Day') duration = 'Full Day'; })),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: _DropdownField('DURATION', duration, _allowsHalfDay ? const ['Full Day', 'Half Day'] : const ['Full Day'], (v) => setState(() => duration = v!)),
                ),
              ],
            )
          else ...[
            _DropdownField('Leave Type', type, widget.leavePolicies.map((item) => '${item['type']}').toList(), (v) => setState(() { type = v!; if (!_allowsHalfDay && duration == 'Half Day') duration = 'Full Day'; })),
            const SizedBox(height: 14),
            _DropdownField('Duration', duration, _allowsHalfDay ? const ['Full Day', 'Half Day'] : const ['Full Day'], (v) => setState(() => duration = v!)),
          ],
          if (duration == 'Half Day') ...[
            const SizedBox(height: 14),
            _DropdownField(
              widget.desktop ? 'LEAVE SESSION' : 'Leave Session',
              halfDaySession,
              const ['morning', 'evening'],
              (v) => setState(() => halfDaySession = v!),
            ),
            const SizedBox(height: 7),
            Text(
              halfDaySession == 'morning'
                  ? 'Morning leave: your attendance will use the admin-configured evening shift rules.'
                  : 'Evening leave: your attendance will use the admin-configured morning shift rules.',
              style: const TextStyle(color: employeeBlue, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
          if (type == 'Earned Leave') ...[
            const SizedBox(height: 8),
            const Text(
              'Earned Leave is paid leave. Your company paid-leave rules apply to this request.',
              style: TextStyle(color: employeeBlue, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          if (widget.desktop)
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(true),
                    child: _DateFieldShell('FROM DATE', fromStr),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(false),
                    child: _DateFieldShell('TO DATE', toStr),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(true),
                    child: _DateFieldShell('From Date', fromStr),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(false),
                    child: _DateFieldShell('To Date', toStr),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'REASON',
                style: TextStyle(
                  color: employeeNavy,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Briefly describe the reason for leave...',
                  filled: true,
                  fillColor: const Color(0xFFFBFCFE),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderSide: const BorderSide(color: employeeLine),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: employeeLine),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Builder(
            builder: (context) {
              final clearButton = OutlinedButton(
                onPressed: () => setState(() {
                  _reasonCtrl.clear();
                  fromDate = DateTime.now();
                  toDate = DateTime.now();
                }),
                style: widget.desktop ? null : OutlinedButton.styleFrom(
                  foregroundColor: employeePurple,
                  minimumSize: const Size.fromHeight(52),
                  side: const BorderSide(color: employeePurple, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Clear'),
              );
              final submitButton = ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_outlined, size: 16),
                label: Text(_submitting ? 'Submitting…' : 'Submit Request'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B72F5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  minimumSize: widget.desktop ? null : const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(widget.desktop ? 8 : 12)),
                ),
              );
              return Align(
                alignment: widget.desktop ? Alignment.centerRight : Alignment.center,
                child: Row(
                  mainAxisSize: widget.desktop ? MainAxisSize.min : MainAxisSize.max,
                  children: [
                    if (widget.desktop) clearButton else Expanded(child: clearButton),
                    SizedBox(width: widget.desktop ? 10 : 12),
                    if (widget.desktop) submitButton else Expanded(child: submitButton),
                  ],
                ),
              );
            },
          ),        ],
      ),
    );
  }

  Widget _premiumMobileForm(BuildContext context, String fromStr, String toStr) {
    final requestedDays = duration == 'Half Day'
        ? .5
        : toDate.difference(fromDate).inDays.abs() + 1.0;
    final mobileFrom = DateFormat('dd-MM-yyyy').format(fromDate);
    final mobileTo = DateFormat('dd-MM-yyyy').format(toDate);
    final reasonBorder = OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0)));
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x120F172A), blurRadius: 12, offset: Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(height: 3, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFBFDBFE), employeeBlue, Color(0xFFBFDBFE)]), borderRadius: BorderRadius.circular(99))),
        const SizedBox(height: 15),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFFEFF6FF), border: Border.all(color: const Color(0xFFBFDBFE)), borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.edit_calendar_rounded, color: Color(0xFF0F52BA), size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Apply for Leave', style: GoogleFonts.inter(color: employeeNavy, fontSize: 19, fontWeight: FontWeight.w800)), const SizedBox(height: 2), Text('Submit a new leave request for\nmanager approval', style: GoogleFonts.inter(color: employeeMuted, fontSize: 10, height: 1.35, fontWeight: FontWeight.w500))])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFE0EDFF), border: Border.all(color: const Color(0xFFBFDBFE)), borderRadius: BorderRadius.circular(99)), child: Text('${requestedDays.toStringAsFixed(1)} Day${requestedDays == 1 ? '' : 's'}', style: GoogleFonts.inter(color: const Color(0xFF072B66), fontSize: 10, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 15),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        const SizedBox(height: 15),
        Text('Leave Type', style: GoogleFonts.inter(color: employeeNavy, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        _PremiumLeaveTypeMenu(
          value: type,
          options: widget.leavePolicies.map((item) => '${item['type']}').toList(),
          onChanged: (value) => setState(() {
            type = value;
            if (!_allowsHalfDay && duration == 'Half Day') duration = 'Full Day';
          }),
        ),
        const SizedBox(height: 15),
        Text('Duration', style: GoogleFonts.inter(color: employeeNavy, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: const Color(0xFFF1F5F9), border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(16)), child: Row(children: [
          Expanded(child: _durationButton('Full Day', duration == 'Full Day', () => setState(() => duration = 'Full Day'))),
          Expanded(child: _durationButton('First Half', duration == 'Half Day' && halfDaySession == 'morning', _allowsHalfDay ? () => setState(() { duration = 'Half Day'; halfDaySession = 'morning'; }) : null)),
          Expanded(child: _durationButton('Second Half', duration == 'Half Day' && halfDaySession == 'evening', _allowsHalfDay ? () => setState(() { duration = 'Half Day'; halfDaySession = 'evening'; }) : null)),
        ])),
        if (type == 'Earned Leave') ...[
          const SizedBox(height: 13),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFEFF6FF), border: Border.all(color: const Color(0xFFBFDBFE)), borderRadius: BorderRadius.circular(14)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.verified_user_rounded, color: Color(0xFF0F52BA), size: 18), const SizedBox(width: 8), Expanded(child: Text('Earned Leave is paid leave. Your company paid-leave rules apply to this request.', style: GoogleFonts.inter(color: const Color(0xFF072B66), fontSize: 10, height: 1.4, fontWeight: FontWeight.w600)))])),
        ],
        const SizedBox(height: 15),
        Row(children: [Expanded(child: InkWell(onTap: () => _pickDate(true), child: _PremiumMobileDateField('From Date', mobileFrom))), const SizedBox(width: 10), Expanded(child: InkWell(onTap: () => _pickDate(false), child: _PremiumMobileDateField('To Date', mobileTo)))]),
        const SizedBox(height: 15),
        Text('REASON', style: GoogleFonts.inter(color: employeeMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .5)),
        const SizedBox(height: 6),
        TextField(controller: _reasonCtrl, minLines: 3, maxLines: 3, decoration: InputDecoration(hintText: 'Briefly describe the reason for leave...', hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12), filled: true, fillColor: const Color(0xFFF8FAFC), contentPadding: const EdgeInsets.all(13), border: reasonBorder, enabledBorder: reasonBorder, focusedBorder: reasonBorder)),
        const SizedBox(height: 15),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () { setState(() { _reasonCtrl.clear(); fromDate = DateTime.now(); toDate = DateTime.now(); duration = 'Full Day'; halfDaySession = 'morning'; }); ScaffoldMessenger.of(context).clearSnackBars(); ScaffoldMessenger.of(context).showSnackBar(employeePremiumSnackBar('Form cleared.', isSuccess: true)); }, style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: employeeNavy, backgroundColor: Colors.white, side: const BorderSide(color: Color(0xFFE2E8F0)), shape: const StadiumBorder()), child: Text('Clear', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800)))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: FilledButton.icon(onPressed: _submitting ? null : _submit, icon: _submitting ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send_rounded, size: 17), label: Text(_submitting ? 'Submitting…' : 'Submit Request'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, elevation: 5, shadowColor: const Color(0x552563EB), shape: const StadiumBorder(), textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800)))),
        ]),
      ]),
    );
  }

  Widget _durationButton(String label, bool selected, VoidCallback? onTap) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(backgroundColor: selected ? const Color(0xFF0F52BA) : Colors.transparent, foregroundColor: selected ? Colors.white : employeeMuted, disabledForegroundColor: const Color(0xFF94A3B8), minimumSize: const Size(0, 40), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    child: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800)),
  );
}

class _PremiumLeaveTypeMenu extends StatelessWidget {
  const _PremiumLeaveTypeMenu({required this.value, required this.options, required this.onChanged});
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => MenuAnchor(
      alignmentOffset: const Offset(0, 2),
      style: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
        maximumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 190)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        elevation: const WidgetStatePropertyAll(7),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.white),
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(2), side: const BorderSide(color: Color(0xFF94A3B8)))),
      ),
      menuChildren: options.map((option) {
        final selected = option == value;
        return MenuItemButton(
          onPressed: () => onChanged(option),
          style: ButtonStyle(padding: const WidgetStatePropertyAll(EdgeInsets.zero), minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0))),
          child: Container(width: constraints.maxWidth, height: 38, padding: const EdgeInsets.symmetric(horizontal: 40), alignment: Alignment.centerLeft, color: selected ? employeeBlue : Colors.white, child: Text(option, style: GoogleFonts.inter(color: selected ? Colors.white : employeeNavy, fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
        );
      }).toList(),
      builder: (context, controller, child) => InkWell(
        onTap: controller.isOpen ? controller.close : controller.open,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), border: Border.all(color: employeeBlue, width: 1.3), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [const Icon(Icons.event_note_rounded, color: Color(0xFF0F52BA), size: 19), const SizedBox(width: 12), Expanded(child: Text(value, style: GoogleFonts.inter(color: employeeNavy, fontSize: 13, fontWeight: FontWeight.w600))), const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF475569), size: 20)]),
        ),
      ),
    ),
  );
}

class _CompactLeaveCalendar extends StatefulWidget {
  const _CompactLeaveCalendar({required this.initialDate});
  final DateTime initialDate;

  @override
  State<_CompactLeaveCalendar> createState() => _CompactLeaveCalendarState();
}

class _CompactLeaveCalendarState extends State<_CompactLeaveCalendar> {
  late DateTime _shownMonth;

  @override
  void initState() {
    super.initState();
    _shownMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
  }

  void _moveMonth(int offset) => setState(() => _shownMonth = DateTime(_shownMonth.year, _shownMonth.month + offset));

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(_shownMonth.year, _shownMonth.month, 1).weekday % 7;
    final dayCount = DateUtils.getDaysInMonth(_shownMonth.year, _shownMonth.month);
    final totalCells = ((firstWeekday + dayCount + 6) ~/ 7) * 7;
    const days = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 34),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 310,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Text(DateFormat('MMMM, yyyy').format(_shownMonth), style: GoogleFonts.inter(color: employeeNavy, fontSize: 12, fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => _moveMonth(-1), icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 21), color: const Color(0xFF334155), splashRadius: 18),
              IconButton(onPressed: () => _moveMonth(1), icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 21), color: const Color(0xFF334155), splashRadius: 18),
            ]),
            const SizedBox(height: 3),
            Row(children: days.map((day) => Expanded(child: Center(child: Text(day, style: GoogleFonts.inter(color: const Color(0xFF0F172A), fontSize: 10, fontWeight: FontWeight.w700))))).toList()),
            const SizedBox(height: 5),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: totalCells,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisExtent: 28),
              itemBuilder: (_, index) {
                final day = index - firstWeekday + 1;
                if (day < 1 || day > dayCount) return const SizedBox.shrink();
                final selected = widget.initialDate.year == _shownMonth.year && widget.initialDate.month == _shownMonth.month && widget.initialDate.day == day;
                return InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => Navigator.pop(context, DateTime(_shownMonth.year, _shownMonth.month, day)),
                  child: Center(
                    child: Container(
                      width: 25,
                      height: 25,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: selected ? employeeBlue : Colors.transparent, borderRadius: BorderRadius.circular(4)),
                      child: Text('$day', style: GoogleFonts.robotoMono(color: selected ? Colors.white : employeeNavy, fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 17, color: Color(0xFFE2E8F0)),
            Row(children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('Clear', style: GoogleFonts.inter(color: employeeBlue, fontSize: 11, fontWeight: FontWeight.w700))),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context, DateTime.now()), child: Text('Today', style: GoogleFonts.inter(color: employeeBlue, fontSize: 11, fontWeight: FontWeight.w700))),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _PremiumMobileDateField extends StatelessWidget {
  const _PremiumMobileDateField(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: GoogleFonts.inter(color: employeeNavy, fontSize: 12, fontWeight: FontWeight.w800)),
      const SizedBox(height: 7),
      Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          Expanded(child: Text(value, style: GoogleFonts.robotoMono(color: employeeNavy, fontSize: 11, fontWeight: FontWeight.w600))),
          const Icon(Icons.calendar_today_outlined, size: 15, color: Color(0xFF334155)),
        ]),
      ),
    ],
  );
}

class _DateFieldShell extends StatelessWidget {
  const _DateFieldShell(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: employeeNavy,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFBFCFE),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: employeeLine),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: employeeMuted,
            ),
            const SizedBox(width: 10),
            Text(
              value,
              style: const TextStyle(
                color: employeeNavy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _DropdownField extends StatelessWidget {
  const _DropdownField(this.label, this.value, this.items, this.onChanged);
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: employeeNavy,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFFFBFCFE),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderSide: const BorderSide(color: employeeLine),
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: employeeLine),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: onChanged,
      ),
    ],
  );
}

// Retained for the legacy compact balance view used by older routes.
// ignore: unused_element
class _MobileLeaveBalance extends StatelessWidget {
  const _MobileLeaveBalance({required this.balances});
  final List<dynamic> balances;

  Color _colorFor(String type) {
    if (type.contains('Sick')) return employeePurple;
    if (type.contains('Earned')) return employeeBlue;
    if (type.contains('Optional')) return employeeOrange;
    return employeeGreen;
  }

  IconData _iconFor(String type) {
    if (type.contains('Sick')) return Icons.medical_services_outlined;
    if (type.contains('Earned')) return Icons.calendar_month_outlined;
    if (type.contains('Optional')) return Icons.event_available_outlined;
    return Icons.calendar_today_outlined;
  }

  @override
  Widget build(BuildContext context) => EmployeeCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Leave Balance', style: TextStyle(color: employeeNavy, fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/employee/leave', arguments: 'requests'),
              icon: const Text('View Details'),
              label: const Icon(Icons.chevron_right_rounded, size: 20),
              style: TextButton.styleFrom(
                foregroundColor: employeeBlue,
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (balances.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: Text('No balance data available', style: TextStyle(color: employeeMuted))),
          )
        else
          Row(
            children: balances.take(4).map((balance) {
              final type = (balance['type'] ?? 'Leave').toString();
              final total = (balance['total'] as num?)?.toInt() ?? 0;
              final used = (balance['used'] as num?)?.toInt() ?? 0;
              final remaining = (total - used).clamp(0, total).toInt();
              final color = _colorFor(type);
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: color.withValues(alpha: 0.20)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                        child: Icon(_iconFor(type), color: color, size: 19),
                      ),
                      const SizedBox(height: 7),
                      Text(type.replaceAll(' ', '\n'), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: employeeMuted, fontSize: 11, fontWeight: FontWeight.w700, height: 1.12)),
                      const SizedBox(height: 7),
                      Text('$remaining', style: TextStyle(color: color, fontSize: 25, fontWeight: FontWeight.w800)),
                      Text('of $total', style: const TextStyle(color: employeeMuted, fontSize: 10, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    ),
  );
}
class _MobileLeave extends StatelessWidget {
  const _MobileLeave({
    required this.mode,
    required this.loading,
    required this.error,
    required this.balances,
    required this.requests,
    required this.onRefresh,
    required this.onCancel,
  });

  final String mode;
  final bool loading;
  final String? error;
  final List<dynamic> balances;
  final List<dynamic> requests;
  final VoidCallback onRefresh;
  final ValueChanged<dynamic> onCancel;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MobileEmployeeHeader(),
          const SizedBox(height: 20),
          _LeaveLoadError(message: error!, onRetry: onRefresh),
        ],
      );
    }

    if (mode == 'requests') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MobileEmployeeHeader(),
          const SizedBox(height: 14),
          const EmployeePageTitle(title: 'My Requests'),
          const SizedBox(height: 20),
          _RequestList(requests: requests, onCancel: onCancel),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PremiumLeaveHeading(balances: balances),
        const SizedBox(height: 16),
        _PremiumLeaveBalance(
          balances: balances,
          onDetails: () => Navigator.pushNamed(context, '/employee/leave', arguments: 'requests'),
        ),
        const SizedBox(height: 16),
        _LeaveForm(desktop: false, leavePolicies: _applicableLeavePolicies(balances), onSuccess: onRefresh),
      ],
    );
  }
}

class _PremiumLeaveHeading extends StatelessWidget {
  const _PremiumLeaveHeading({required this.balances});
  final List<dynamic> balances;

  @override
  Widget build(BuildContext context) {
    final remaining = balances.fold<num>(0, (sum, balance) {
      if (balance is! Map) return sum;
      final total = balance['total'] as num? ?? 0;
      final used = balance['used'] as num? ?? 0;
      return sum + (total - used).clamp(0, total);
    });
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hello, Okash', style: GoogleFonts.inter(color: employeeNavy, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.5)),
        const SizedBox(height: 4),
        Row(children: [
          Text('Leave Balance & Requests', style: GoogleFonts.inter(color: employeeMuted, fontSize: 11, fontWeight: FontWeight.w500)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('•', style: TextStyle(color: Color(0xFF94A3B8)))),
          Text('EMP1008', style: GoogleFonts.robotoMono(color: employeeBlue, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ])),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: const Color(0xFFE0EDFF), border: Border.all(color: const Color(0xFFBFDBFE)), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.event_available_rounded, color: Color(0xFF0F52BA), size: 14),
          const SizedBox(width: 5),
          Text('${_days(remaining)} Days Left', style: GoogleFonts.inter(color: const Color(0xFF072B66), fontSize: 10, fontWeight: FontWeight.w800)),
        ]),
      ),
    ]);
  }
}

class _PremiumLeaveBalance extends StatelessWidget {
  const _PremiumLeaveBalance({required this.balances, required this.onDetails});
  final List<dynamic> balances;
  final VoidCallback onDetails;

  Map<String, dynamic> _balance(String keyword) {
    return balances.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).firstWhere(
          (item) => '${item['type']}'.toLowerCase().contains(keyword),
          orElse: () => <String, dynamic>{'type': keyword == 'earned' ? 'Earned Leave' : 'Sick Leave', 'total': 0, 'used': 0},
        );
  }

  num _number(Object? value) => value is num ? value : num.tryParse('$value') ?? 0;

  @override
  Widget build(BuildContext context) {
    final sick = _balance('sick');
    final earned = _balance('earned');
    return Container(
      height: 264,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0F172A), Color(0xFF1E293B)]),
        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: .40)),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x260F172A), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFF1E293B), border: Border.all(color: const Color(0x553B82F6)), borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.calendar_today_rounded, color: Color(0xFFBFDBFE), size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Leave Balance', style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)), Text('FY ${DateTime.now().year} Annual Quota', style: GoogleFonts.inter(color: const Color(0xFFBFDBFE), fontSize: 10, fontWeight: FontWeight.w600))])),
          TextButton.icon(onPressed: onDetails, iconAlignment: IconAlignment.end, icon: const Icon(Icons.chevron_right_rounded, size: 16), label: Text('View Details', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800)), style: TextButton.styleFrom(foregroundColor: const Color(0xFFDBEAFE), padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99), side: const BorderSide(color: Color(0x553B82F6))))),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _PremiumLeavePod(balance: sick, sick: true, number: _number)),
          const SizedBox(width: 10),
          Expanded(child: _PremiumLeavePod(balance: earned, number: _number)),
        ]),
      ]),
    );
  }
}

class _PremiumLeavePod extends StatelessWidget {
  const _PremiumLeavePod({required this.balance, required this.number, this.sick = false});
  final Map<String, dynamic> balance;
  final num Function(Object?) number;
  final bool sick;
  @override
  Widget build(BuildContext context) {
    final total = number(balance['total']);
    final used = number(balance['used']);
    final left = (total - used).clamp(0, total);
    final pct = total == 0 ? 0.0 : left / total;
    final label = balance['type']?.toString() ?? (sick ? 'Sick Leave' : 'Earned Leave');
    final decoration = sick
        ? BoxDecoration(color: const Color(0xCC1E293B), border: Border.all(color: const Color(0x333B82F6)), borderRadius: BorderRadius.circular(15))
        : BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0F52BA), Color(0xFF1D4ED8)]), borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(color: Color(0x331D4ED8), blurRadius: 12, offset: Offset(0, 5))]);
    return Container(height: 160, padding: const EdgeInsets.all(13), decoration: decoration, child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Icon(sick ? Icons.medical_services_rounded : Icons.event_note_rounded, color: sick ? const Color(0xFFBFDBFE) : Colors.white, size: 17), Text('${(pct * 100).round()}% left', style: GoogleFonts.inter(color: sick ? const Color(0xFFBFDBFE) : Colors.white, fontSize: 9, fontWeight: FontWeight.w700))]),
      const SizedBox(height: 9), Text(label, textAlign: TextAlign.center, style: GoogleFonts.inter(color: sick ? const Color(0xFFDBEAFE) : const Color(0xFFDBEAFE), fontSize: 11, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2), Text(_days(left), style: GoogleFonts.robotoMono(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)), Text('of ${_days(total)} days', style: GoogleFonts.inter(color: sick ? const Color(0xFFBFDBFE) : const Color(0xFFDBEAFE), fontSize: 10)),
      const SizedBox(height: 10), ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: pct, minHeight: 5, backgroundColor: sick ? const Color(0xFF0F172A) : const Color(0xFF1E40AF), valueColor: const AlwaysStoppedAnimation(Colors.white))),
    ]));
  }
}
