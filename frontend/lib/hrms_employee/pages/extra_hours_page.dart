import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/api_config.dart';
import '../../services/auth_service.dart';
import '../shared/employee_ui.dart';

class EmployeeExtraHoursPage extends StatefulWidget {
  const EmployeeExtraHoursPage({super.key});

  @override
  State<EmployeeExtraHoursPage> createState() => _EmployeeExtraHoursPageState();
}

class _EmployeeExtraHoursPageState extends State<EmployeeExtraHoursPage> {
  bool _loading = true;
  List<dynamic> _rows = [];
  Map<String, dynamic> _metrics = {
    'total_year': '0h',
    'this_month_hours': '0h',
    'this_month_detail': '0 sessions logged',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchData());
  }

  List<String> _getBaseUrls() {
    return ['${ApiConfig.baseUrl}/attendance'];
  }

  Future<void> _fetchData() async {
    final token = context.read<AuthService>().token;
    if (token == null) return;

    setState(() => _loading = true);

    for (final base in _getBaseUrls()) {
      try {
        final url = Uri.parse('$base/overtime/my');
        final res = await http
            .get(
              url,
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          if (body['success'] == true && body['data'] != null) {
            if (mounted) {
              setState(() {
                _rows = body['data']['rows'] ?? [];
                _metrics = body['data']['metrics'] ?? _metrics;
                _loading = false;
              });
            }
            return;
          }
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _showLogDialog(BuildContext context) async {
    final dateCtrl = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    final hoursCtrl = TextEditingController(text: '2h 00m');
    final reasonCtrl = TextEditingController();
    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Log Extra Hours'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: dateCtrl,
                  readOnly: true,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2025),
                      lastDate: DateTime(2028),
                    );
                    if (picked != null) {
                      setModalState(() {
                        dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
                      });
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hoursCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Hours worked (e.g. 2h 30m)',
                    prefixIcon: Icon(Icons.schedule),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    hintText: 'Describe tasks completed...',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final token = context.read<AuthService>().token;
                      if (token == null) return;

                      setModalState(() => submitting = true);

                      final payload = {
                        'work_date': dateCtrl.text,
                        'hours_worked': hoursCtrl.text.trim(),
                        'reason': reasonCtrl.text.trim(),
                        'regular_out': '06:00 PM',
                        'actual_out': 'Overtime Session',
                      };

                      bool ok = false;
                      for (final base in _getBaseUrls()) {
                        try {
                          final res = await http.post(
                            Uri.parse('$base/extra-hours/log'),
                            headers: {
                              'Authorization': 'Bearer $token',
                              'Content-Type': 'application/json',
                            },
                            body: jsonEncode(payload),
                          );
                          if (res.statusCode == 200) {
                            ok = true;
                            break;
                          }
                        } catch (_) {}
                      }

                      if (mounted) {
                        Navigator.pop(ctx);
                        if (ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Extra hours logged successfully!'),
                            ),
                          );
                          _fetchData();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to submit extra hours.'),
                            ),
                          );
                        }
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentMonthFormatted = DateFormat(
      'MMMM yyyy',
    ).format(DateTime.now());

    return EmployeeScaffold(
      route: '/employee/extra-hours',
      title: 'Extra Hours',
      subtitle: 'Automatically calculated after clock-out',
      desktopHeaderAction: null,
      desktop: _DesktopExtraHours(
        loading: _loading,
        rows: _rows,
        metrics: _metrics,
        monthLabel: currentMonthFormatted,
        onLogPressed: () {},
      ),
      mobile: _MobileExtraHours(
        loading: _loading,
        rows: _rows,
        metrics: _metrics,
        monthLabel: currentMonthFormatted,
        onLogPressed: () {},
      ),
    );
  }
}

class _DesktopExtraHours extends StatelessWidget {
  const _DesktopExtraHours({
    required this.loading,
    required this.rows,
    required this.metrics,
    required this.monthLabel,
    required this.onLogPressed,
  });

  final bool loading;
  final List<dynamic> rows;
  final Map<String, dynamic> metrics;
  final String monthLabel;
  final VoidCallback onLogPressed;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: _ExtraHoursSummaryCard(
              icon: Icons.calendar_month_outlined,
              label: 'THIS MONTH',
              value: metrics['this_month_hours'] ?? '0h',
              caption: metrics['this_month_detail'] ?? '0 sessions logged',
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: _ExtraHoursSummaryCard(
              icon: Icons.bar_chart_rounded,
              label: 'TOTAL LOGGED',
              value: metrics['total_year'] ?? '0h',
              caption: 'All recorded extra hours',
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      EmployeeCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
              child: SectionTitle(
                'Extra Hours Log',
                trailing: HeaderPill(monthLabel),
              ),
            ),
            const Divider(height: 1, color: employeeLine),
            if (loading)
              const SizedBox(
                height: 230,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (rows.isEmpty)
              _EmptyExtraHoursState(onLogPressed: onLogPressed)
            else
              SimpleTable(
                minWidth: 790,
                columns: const [
                  'DATE',
                  'DAY',
                  'REGULAR OUT',
                  'ACTUAL OUT',
                  'EXTRA HRS',
                ],
                rows: rows
                    .map(
                      (r) => [
                        Text(
                          r['date_str']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(r['day_str']?.toString() ?? ''),
                        Text(r['regular_out']?.toString() ?? '—'),
                        Text(r['actual_out']?.toString() ?? '—'),
                        Text(
                          r['hours_minutes']?.toString() ?? '',
                          style: const TextStyle(
                            color: employeeBlue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    )
                    .toList(),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 14, 22, 16),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: employeeMuted,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Extra hours are kept for attendance records only.',
                    style: TextStyle(color: employeeMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ExtraHoursSummaryCard extends StatelessWidget {
  const _ExtraHoursSummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) => EmployeeCard(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
    child: Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: employeeBlue, size: 27),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: employeeMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: employeeNavy,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              caption,
              style: const TextStyle(color: employeeMuted, fontSize: 13),
            ),
          ],
        ),
      ],
    ),
  );
}

class _EmptyExtraHoursState extends StatelessWidget {
  const _EmptyExtraHoursState({required this.onLogPressed});

  final VoidCallback onLogPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 230,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF2FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.schedule_outlined,
              color: employeeBlue,
              size: 31,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No extra hours logged this month',
            style: TextStyle(
              color: employeeNavy,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Use Log Hours to add a record.',
            style: TextStyle(color: employeeMuted),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onLogPressed,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Log Hours'),
          ),
        ],
      ),
    ),
  );
}

class _MobileExtraHours extends StatelessWidget {
  const _MobileExtraHours({
    required this.loading,
    required this.rows,
    required this.metrics,
    required this.monthLabel,
    required this.onLogPressed,
  });

  final bool loading;
  final List<dynamic> rows;
  final Map<String, dynamic> metrics;
  final String monthLabel;
  final VoidCallback onLogPressed;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const MobileEmployeeHeader(),
      const SizedBox(height: 14),
      EmployeePageTitle(
        title: 'Extra Hours',
        trailing: PrimaryButton(
          label: 'Log Extra Hours',
          icon: Icons.add_circle_outline,
          color: employeeOrange,
          onPressed: onLogPressed,
        ),
      ),
      const SizedBox(height: 20),
      EmployeeCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'This Month',
                        style: TextStyle(
                          color: employeeNavy,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        monthLabel,
                        style: const TextStyle(color: employeeMuted),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Total Extra Hours',
                      style: TextStyle(color: employeeMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      metrics['this_month_hours'] ?? '0h',
                      style: const TextStyle(
                        color: employeeOrange,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 28, color: Color(0xFFFFCAA2)),
            Row(
              children: [
                Expanded(
                  child: _ExtraSummary(
                    Icons.schedule,
                    'This month',
                    metrics['this_month_hours'] ?? '0h',
                  ),
                ),
                Expanded(
                  child: _ExtraSummary(
                    Icons.description_outlined,
                    'Sessions',
                    rows.length.toString(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      EmployeeCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Extra Hours Log',
                style: TextStyle(
                  color: employeeNavy,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'No extra hours recorded.',
                    style: TextStyle(color: employeeMuted),
                  ),
                ),
              )
            else
              ...rows.map((r) => _MobileExtraRow(r)),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const InfoBanner(
        'Extra hours are recorded for attendance history only. They do not generate additional pay.',
        color: employeeOrange,
      ),
    ],
  );
}

class _ExtraSummary extends StatelessWidget {
  const _ExtraSummary(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: employeeOrange, size: 27),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: employeeMuted)),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(
          color: employeeOrange,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _MobileExtraRow extends StatelessWidget {
  const _MobileExtraRow(this.r);
  final dynamic r;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: employeeLine)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 21,
            backgroundColor: Color(0xFFEAF2FF),
            child: Icon(
              Icons.calendar_today_outlined,
              color: employeeBlue,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r['date_str']} 2026 · ${r['day_str']}',
                  style: const TextStyle(
                    color: employeeNavy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${r['regular_out']} – ${r['actual_out']}',
                  style: const TextStyle(color: employeeMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                r['hours_minutes']?.toString() ?? '',
                style: const TextStyle(
                  color: employeeOrange,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(width: 7),
          const Icon(Icons.chevron_right_rounded, color: employeeMuted),
        ],
      ),
    );
  }
}
