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
    final reasonCtrl = TextEditingController();
    var selectedDate = DateTime.now();
    var selectedDuration = '1h 00m';
    bool submitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 320),
        reverseDuration: Duration(milliseconds: 220),
      ),
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            MediaQuery.viewInsetsOf(context).bottom + 12,
          ),
          child: SafeArea(
            top: false,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFDCE4F0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x3B07143F),
                    blurRadius: 26,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Log Extra Hours',
                              style: TextStyle(
                                color: employeeNavy,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Record additional shift time',
                              style: TextStyle(
                                color: employeeMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Material(
                        color: const Color(0xFFF1F5F9),
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: submitting
                              ? null
                              : () => Navigator.pop(sheetContext),
                          customBorder: const CircleBorder(),
                          child: const SizedBox(
                            width: 34,
                            height: 34,
                            child: Icon(Icons.close_rounded, size: 19),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Divider(height: 1, color: employeeLine),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _ExtraHoursSheetField(
                          label: 'Date',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: submitting
                                ? null
                                : () async {
                                    final picked = await showDatePicker(
                                      context: sheetContext,
                                      initialDate: selectedDate,
                                      firstDate: DateTime(2025),
                                      lastDate: DateTime(2028),
                                    );
                                    if (picked != null) {
                                      setModalState(
                                        () => selectedDate = picked,
                                      );
                                    }
                                  },
                            child: _SheetValue(
                              value: DateFormat(
                                'dd-MM-yyyy',
                              ).format(selectedDate),
                              icon: Icons.calendar_today_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ExtraHoursSheetField(
                          label: 'Duration',
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedDuration,
                            isExpanded: true,
                            decoration: _sheetInputDecoration(),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                            items:
                                const [
                                      '0h 30m',
                                      '1h 00m',
                                      '1h 30m',
                                      '2h 00m',
                                      '3h 00m',
                                    ]
                                    .map(
                                      (value) => DropdownMenuItem(
                                        value: value,
                                        child: Text(value),
                                      ),
                                    )
                                    .toList(),
                            onChanged: submitting
                                ? null
                                : (value) => setModalState(
                                    () => selectedDuration =
                                        value ?? selectedDuration,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ExtraHoursSheetField(
                    label: 'Task / Reason',
                    child: TextField(
                      controller: reasonCtrl,
                      enabled: !submitting,
                      maxLines: 1,
                      decoration: _sheetInputDecoration(
                        hintText: 'e.g. Client deployment support',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1769E0), Color(0xFF2563EB)],
                        ),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x3D1769E0),
                            blurRadius: 12,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: submitting
                            ? null
                            : () async {
                                final token = this.context
                                    .read<AuthService>()
                                    .token;
                                if (token == null) return;
                                setModalState(() => submitting = true);
                                final payload = {
                                  'work_date': DateFormat(
                                    'yyyy-MM-dd',
                                  ).format(selectedDate),
                                  'hours_worked': selectedDuration,
                                  'reason': reasonCtrl.text.trim(),
                                  'regular_out': '06:00 PM',
                                  'actual_out': 'Overtime Session',
                                };
                                var ok = false;
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
                                if (!mounted || !sheetContext.mounted) return;
                                Navigator.pop(sheetContext);
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  employeePremiumSnackBar(
                                    ok
                                        ? 'Extra hours logged successfully.'
                                        : 'Failed to submit extra hours.',
                                    isSuccess: ok,
                                    isError: !ok,
                                  ),
                                );
                                if (ok) _fetchData();
                              },
                        child: submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Extra Hours',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    reasonCtrl.dispose();
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
        onLogPressed: () => _showLogDialog(context),
      ),
      mobile: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // Preserve comfortable gutters while allowing the desktop mobile
          // preview to use a wider, more readable card measure.
          constraints: const BoxConstraints(maxWidth: 440),
          child: _MobileExtraHours(
            loading: _loading,
            rows: _rows,
            metrics: _metrics,
            monthLabel: currentMonthFormatted,
            onLogPressed: () => _showLogDialog(context),
          ),
        ),
      ),
    );
  }
}

InputDecoration _sheetInputDecoration({String? hintText}) => InputDecoration(
  hintText: hintText,
  hintStyle: const TextStyle(color: Color(0xFF8795AC), fontSize: 12),
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  filled: true,
  fillColor: const Color(0xFFF8FAFC),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: Color(0xFFDCE4F0)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: employeeBlue, width: 1.5),
  ),
);

class _ExtraHoursSheetField extends StatelessWidget {
  const _ExtraHoursSheetField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: employeeNavy,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 6),
      child,
    ],
  );
}

class _SheetValue extends StatelessWidget {
  const _SheetValue({required this.value, required this.icon});
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDCE4F0)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: employeeNavy,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Icon(icon, size: 16, color: employeeNavy),
      ],
    ),
  );
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
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    final fullName = '${user?['fullName'] ?? user?['name'] ?? 'Employee'}'
        .trim();
    final firstName = fullName.isEmpty ? 'Employee' : fullName.split(' ').first;
    final staffId =
        '${user?['staffId'] ?? user?['staff_id'] ?? user?['employee_id'] ?? ''}'
            .trim();
    final monthHours = '${metrics['this_month_hours'] ?? '0h'}';
    final sessions = rows.length.toString();

    return Transform.translate(
      offset: const Offset(0, -8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Hello, $firstName',
                          style: const TextStyle(
                            color: employeeNavy,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (staffId.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 7),
                            child: Icon(
                              Icons.circle,
                              size: 4,
                              color: employeeMuted,
                            ),
                          ),
                          Text(
                            staffId,
                            style: const TextStyle(
                              color: employeeBlue,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .35,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Extra Hours',
                      style: TextStyle(
                        color: employeeNavy,
                        fontSize: 25,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.45,
                      ),
                    ),
                  ],
                ),
              ),
              _ExtraHoursCta(onPressed: onLogPressed),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F172A), Color(0xFF17233A)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF294A7A)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x240A1B3B),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  height: 3,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF38BDF8),
                        employeeBlue,
                        Color(0xFF2457D6),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
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
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  monthLabel,
                                  style: const TextStyle(
                                    color: Color(0xFFB8CEEF),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'TOTAL EXTRA HOURS',
                                style: TextStyle(
                                  color: Color(0xFFB8CEEF),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .6,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                monthHours,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Divider(color: Color(0x334D8AE5), height: 1),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _PremiumExtraMetric(
                              icon: Icons.schedule_rounded,
                              label: 'This month',
                              value: monthHours,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _PremiumExtraMetric(
                              icon: Icons.description_outlined,
                              label: 'Sessions',
                              value: sessions,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: employeeLine),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x120A1B3B),
                  blurRadius: 15,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 3, color: const Color(0xFF8DB9FF)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(17, 16, 17, 17),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF3FF),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: const Color(0xFFBFDBFE),
                              ),
                            ),
                            child: const Icon(
                              Icons.more_time_rounded,
                              color: employeeBlue,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Extra Hours Log',
                              style: TextStyle(
                                color: employeeNavy,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          _EntryBadge(count: rows.length),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (loading)
                        const SizedBox(
                          height: 112,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (rows.isEmpty)
                        _PremiumEmptyExtraHours(onPressed: onLogPressed)
                      else
                        ...rows.map((row) => _MobileExtraRow(row)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: employeeBlue, size: 19),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Extra hours are recorded for attendance history only. They do not generate additional pay.',
                    style: TextStyle(
                      color: Color(0xFF16427B),
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtraHoursCta extends StatelessWidget {
  const _ExtraHoursCta({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1769E0), Color(0xFF2558D9)],
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x421769E0),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_circle_outline_rounded,
              color: Colors.white,
              size: 17,
            ),
            SizedBox(width: 6),
            Text(
              'Log Extra Hours',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PremiumExtraMetric extends StatelessWidget {
  const _PremiumExtraMetric({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF29466E)),
    ),
    child: SizedBox(
      height: 116,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFF8AB9FF), size: 20),
          const SizedBox(height: 7),
          Text(
            label,
            style: const TextStyle(color: Color(0xFFB8CEEF), fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _EntryBadge extends StatelessWidget {
  const _EntryBadge({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$count ${count == 1 ? 'Entry' : 'Entries'}',
      style: const TextStyle(
        color: Color(0xFF334155),
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _PremiumEmptyExtraHours extends StatelessWidget {
  const _PremiumEmptyExtraHours({required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _DashedRoundedBorderPainter(),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 27),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F9FF),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Icon(
              Icons.hourglass_empty_rounded,
              color: employeeBlue,
              size: 23,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'No extra hours recorded.',
            style: TextStyle(
              color: employeeMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(132, 31),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              foregroundColor: employeeBlue,
              side: const BorderSide(color: Color(0xFFBFDBFE)),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: const Text('Add First Session'),
          ),
        ],
      ),
    ),
  );
}

class _DashedRoundedBorderPainter extends CustomPainter {
  const _DashedRoundedBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(15)),
      );
    final paint = Paint()
      ..color = const Color(0xFFD6E1F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (var start = 0.0; start < metric.length; start += 7) {
        canvas.drawPath(metric.extractPath(start, start + 3.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) =>
      false;
}

/// The compact orange extra-hours surface follows the supplied mobile
/// reference exactly: it deliberately stays lighter than the other blue
/// employee pages because orange communicates additional time.
// ignore: unused_element
class _ReferenceExtraHours extends StatelessWidget {
  const _ReferenceExtraHours({
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
                      metrics['this_month_hours'] ?? '0h 0m',
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
                  child: _ReferenceMetric(
                    icon: Icons.schedule,
                    label: 'This month',
                    value: metrics['this_month_hours'] ?? '0h 0m',
                  ),
                ),
                Expanded(
                  child: _ReferenceMetric(
                    icon: Icons.description_outlined,
                    label: 'Sessions',
                    value: rows.length.toString(),
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
                padding: EdgeInsets.symmetric(vertical: 23),
                child: Center(
                  child: Text(
                    'No extra hours recorded.',
                    style: TextStyle(color: employeeMuted),
                  ),
                ),
              )
            else
              ...rows.map((row) => _MobileExtraRow(row)),
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

class _ReferenceMetric extends StatelessWidget {
  const _ReferenceMetric({
    required this.icon,
    required this.label,
    required this.value,
  });
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
