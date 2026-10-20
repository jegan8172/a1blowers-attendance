import 'package:flutter/material.dart';
import '../../shared/theme/admin_surface_palette.dart';

import '../../../services/hrms_payroll_api.dart';
import '../../shared/widgets/admin_top_nav.dart';

abstract final class _PayrollColors {
  static const blue = Color(0xFFE3162A);
  static const navy = Color(0xFF081B3C);
  static const page = Color(0xFFF7F8FA);
}

class PayrollPage extends StatefulWidget {
  const PayrollPage({super.key, this.settingsAction, this.inSettingsDialog = false});

  final String? settingsAction;
  final bool inSettingsDialog;

  static Widget builder(BuildContext context) => const PayrollPage();

  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  bool _openedSettingsAction = false;
  late int year;
  late int month;
  String employee = 'All Employees';
  String status = 'All Status';
  List<_PayrollRow> rows = [];
  List<String> employeeNames = const ['All Employees'];
  List<_MonthOption> months = [];
  String kpiTotal = '₹0';
  int kpiEmployees = 0;
  int kpiPaid = 0;
  int kpiPending = 0;
  int kpiWorkingDays = 0;
  bool loading = true;
  bool generating = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    year = now.year;
    month = now.month;
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final action = widget.settingsAction ??
        (ModalRoute.of(context)?.settings.arguments as Map?)?['settingsAction'];
    if (_openedSettingsAction || action != 'payrollPolicy') return;
    _openedSettingsAction = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _editPolicy();
      if (widget.inSettingsDialog && mounted) Navigator.of(context).pop();
    });
  }

  String get _monthKey => '$year-${month.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await HrmsPayrollApi.list(
        year: year,
        month: month,
        employee: employee,
        status: status,
      );
      final items = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map((item) => _PayrollRow.fromApi(Map<String, dynamic>.from(item)))
          .toList();
      final kpis = Map<String, dynamic>.from(data['kpis'] as Map? ?? {});
      final names = <String>{'All Employees'};
      names.addAll((data['employees'] as List? ?? []).map((e) => e.toString()));
      final monthItems = (data['months'] as List? ?? [])
          .whereType<Map>()
          .map((item) => _MonthOption.fromApi(Map<String, dynamic>.from(item)))
          .toList();
      if (!mounted) return;
      setState(() {
        rows = items;
        employeeNames = names.toList();
        if (!employeeNames.contains(employee)) employee = 'All Employees';
        months = monthItems;
        year = _asInt(data['year'], year);
        month = _asInt(data['month'], month);
        kpiTotal = (kpis['totalPayrollLabel'] ?? '₹0').toString();
        kpiEmployees = _asInt(kpis['employees'], 0);
        kpiPaid = _asInt(kpis['paid'], 0);
        kpiPending = _asInt(kpis['pending'], 0) + _asInt(kpis['draft'], 0);
        kpiWorkingDays = _asInt(kpis['totalWorkingDays'], 0);
        loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        error = err.toString().replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  int _asInt(dynamic value, int fallback) {
    if (value is int) return value;
    return int.tryParse('$value') ?? fallback;
  }

  Future<void> _generate() async {
    setState(() => generating = true);
    try {
      await HrmsPayrollApi.generate(year: year, month: month);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Payroll run generated for every employee with configured compensation.',
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Future<void> _markPaid(_PayrollRow row) async {
    if (row.itemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generate payroll for this month first.')),
      );
      return;
    }
    try {
      await HrmsPayrollApi.markPaid(row.itemId!);
      await _load();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _viewHistory(_PayrollRow row) async {
    try {
      final items = await HrmsPayrollApi.deductionHistory(
        profileId: row.profileId,
        year: year,
        month: month,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${row.name} — deduction history'),
          content: SizedBox(
            width: 520,
            child: items.isEmpty
                ? const Text(
                    'No late or absent salary deductions were generated for this payroll period.',
                  )
                : SingleChildScrollView(
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Type')),
                        DataColumn(label: Text('Late')),
                        DataColumn(label: Text('Amount')),
                      ],
                      rows: items
                          .map(
                            (item) => DataRow(
                              cells: [
                                DataCell(Text('${item['attendance_date']}')),
                                DataCell(
                                  Text(
                                    '${item['deduction_type']}' == 'late'
                                        ? 'Late'
                                        : 'Absent',
                                  ),
                                ),
                                DataCell(
                                  Text('${item['late_minutes'] ?? 0} min'),
                                ),
                                DataCell(Text('₹${item['amount']}')),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
    }
  }

  Future<void> _overrideCycle(_PayrollRow row) async {
    if (row.salaryType != 'Flexible') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Only Flexible employees can have a custom payroll cycle.',
          ),
        ),
      );
      return;
    }
    final initial = DateTimeRange(
      start: DateTime.parse(row.periodStart),
      end: DateTime.parse(row.periodEnd),
    );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: initial,
      helpText: 'Custom payroll cycle for ${row.name}',
    );
    if (picked == null || !mounted) return;
    try {
      await HrmsPayrollApi.saveCycleOverride(
        profileId: row.profileId,
        year: year,
        month: month,
        periodStart: picked.start,
        periodEnd: picked.end,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Custom payroll cycle saved.')),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: mobile
          ? const AdminMobileBottomNav(activeRoute: '/admin/payroll')
          : null,
      body: Column(
        children: [
          const AdminTopNav(activeRoute: '/admin/payroll'),
          Expanded(
            child: loading && rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : error != null && rows.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(error!, textAlign: TextAlign.center),
                        ),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      mobile ? 16 : 28,
                      18,
                      mobile ? 16 : 28,
                      28,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1580),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PayrollHeader(
                              generating: generating,
                              onGenerate: _generate,
                            ),
                            const SizedBox(height: 17),
                            _PayrollKpis(
                              total: kpiTotal,
                              employees: kpiEmployees,
                              paid: kpiPaid,
                              pending: kpiPending,
                              workingDays: kpiWorkingDays,
                            ),
                            const SizedBox(height: 16),
                            if (loading)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: LinearProgressIndicator(minHeight: 2),
                              ),
                            _PayrollPanel(
                              monthKey: _monthKey,
                              months: months,
                              employee: employee,
                              status: status,
                              employees: employeeNames,
                              rows: rows,
                              onMonthChanged: (value) {
                                if (value == null) return;
                                final parts = value.split('-');
                                year = int.parse(parts[0]);
                                month = int.parse(parts[1]);
                                _load();
                              },
                              onEmployeeChanged: (value) {
                                employee = value!;
                                _load();
                              },
                              onStatusChanged: (value) {
                                status = value!;
                                _load();
                              },
                              onReset: () {
                                employee = 'All Employees';
                                status = 'All Status';
                                _load();
                              },
                              onMarkPaid: _markPaid,
                              onHistory: _viewHistory,
                              onCycleOverride: _overrideCycle,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _editPolicy() async {
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => const _PayrollPolicyDialog(),
      );
      if (saved == true) _load();
    } catch (err) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err.toString().replaceFirst('Exception: ', '')),
          ),
        );
    }
  }
}

class _PayrollPolicyDialog extends StatefulWidget {
  const _PayrollPolicyDialog();
  @override
  State<_PayrollPolicyDialog> createState() => _PayrollPolicyDialogState();
}

class _PayrollPolicyDialogState extends State<_PayrollPolicyDialog> {
  Set<int> offDays = {0};
  bool approvedLeave = true;
  bool explicitAbsence = true;
  bool missingAttendance = false;
  bool autoGenerate = false;
  bool loading = true;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await HrmsPayrollApi.policy();
    if (!mounted) return;
    setState(() {
      offDays = ((data['weeklyOffDays'] as List? ?? [0])
          .map((v) => int.tryParse('$v') ?? 0)
          .toSet());
      approvedLeave = data['deductApprovedLeave'] == true;
      explicitAbsence = data['deductExplicitAbsence'] == true;
      missingAttendance = data['missingAttendanceIsAbsent'] == true;
      autoGenerate = data['autoGenerate'] == true;
      loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await HrmsPayrollApi.savePolicy({
        'weeklyOffDays': offDays.toList()..sort(),
        'deductApprovedLeave': approvedLeave,
        'deductExplicitAbsence': explicitAbsence,
        'missingAttendanceIsAbsent': missingAttendance,
        'autoGenerate': autoGenerate,
      });
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Payroll policy'),
    content: loading
        ? const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          )
        : SingleChildScrollView(
            child: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Weekly off days'),
                  Wrap(
                    children: List.generate(7, (day) {
                      const labels = [
                        'Sun',
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                      ];
                      return FilterChip(
                        label: Text(labels[day]),
                        selected: offDays.contains(day),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            offDays.add(day);
                          } else {
                            offDays.remove(day);
                          }
                        }),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Salary is calculated using the actual working days in each payroll period.',
                    style: TextStyle(color: Color(0xFF657087), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  const Text('Payroll generation mode'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Manual'),
                        selected: !autoGenerate,
                        onSelected: (_) => setState(() => autoGenerate = false),
                      ),
                      ChoiceChip(
                        label: const Text('Auto'),
                        selected: autoGenerate,
                        onSelected: (_) => setState(() => autoGenerate = true),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      autoGenerate
                          ? 'Auto refreshes unpaid payroll once each new day. Paid rows are never changed.'
                          : 'Use Generate payroll whenever you want to update this month.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Deduct approved leave'),
                    value: approvedLeave,
                    onChanged: (value) => setState(() => approvedLeave = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Deduct explicit absence'),
                    value: explicitAbsence,
                    onChanged: (value) =>
                        setState(() => explicitAbsence = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Treat missing attendance as absence'),
                    value: missingAttendance,
                    onChanged: (value) =>
                        setState(() => missingAttendance = value),
                  ),
                ],
              ),
            ),
          ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : _save,
        child: Text(saving ? 'Saving…' : 'Save policy'),
      ),
    ],
  );
}

class _MonthOption {
  const _MonthOption({
    required this.year,
    required this.month,
    required this.label,
  });
  final int year, month;
  final String label;
  String get key => '$year-${month.toString().padLeft(2, '0')}';

  factory _MonthOption.fromApi(Map<String, dynamic> json) {
    int asInt(dynamic value) =>
        value is int ? value : int.tryParse('$value') ?? 0;
    return _MonthOption(
      year: asInt(json['year']),
      month: asInt(json['month']),
      label: (json['label'] ?? '').toString(),
    );
  }
}

class _PayrollHeader extends StatelessWidget {
  const _PayrollHeader({
    required this.generating,
    required this.onGenerate,
  });
  final bool generating;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: AdminPageHeader(title: 'Payroll')),
        FilledButton.icon(
          onPressed: generating ? null : onGenerate,
          icon: generating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.playlist_add_check_rounded),
          label: Text(generating ? 'Generating…' : 'Generate payroll'),
          style: FilledButton.styleFrom(
            backgroundColor: _PayrollColors.blue,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }
}

class _PayrollKpis extends StatelessWidget {
  const _PayrollKpis({
    required this.total,
    required this.employees,
    required this.paid,
    required this.pending,
    required this.workingDays,
  });
  final String total;
  final int employees, paid, pending, workingDays;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _PayrollKpi(
        'Working days',
        '$workingDays',
        'For this payroll month',
        Icons.calendar_month_outlined,
        _PayrollColors.blue,
      ),
      _PayrollKpi(
        'This month net',
        total,
        'Present + late days vs working days',
        Icons.account_balance_wallet_outlined,
        _PayrollColors.blue,
      ),
      _PayrollKpi(
        'Employees',
        '$employees',
        'Active / on leave staff',
        Icons.groups_outlined,
        const Color(0xFF158C20),
      ),
      _PayrollKpi(
        'Paid',
        '$paid',
        'Marked paid',
        Icons.check_circle_outline_rounded,
        const Color(0xFF158C20),
      ),
      _PayrollKpi(
        'Unpaid',
        '$pending',
        'Draft or pending rows',
        Icons.pending_actions_outlined,
        const Color(0xFFFF6500),
      ),
    ];
    return LayoutBuilder(
      builder: (_, constraints) {
        final mobile = constraints.maxWidth < 600;
        final columns = mobile
            ? 4
            : constraints.maxWidth < 700
            ? 1
            : constraints.maxWidth < 1100
            ? 2
            : 5;
        final spacing = mobile ? 8.0 : 16.0;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: mobile ? 8 : 16,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(),
        );
      },
    );
  }
}

class _PayrollKpi extends StatelessWidget {
  const _PayrollKpi(
    this.label,
    this.value,
    this.caption,
    this.icon,
    this.color,
  );
  final String label, value, caption;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AdminSurfacePalette.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    if (compact) {
      return Container(
        height: 80,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: palette.surface,
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
              style: TextStyle(color: palette.mutedText, fontSize: 11),
            ),
            const Spacer(),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      height: 116,
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 9),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(13),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C071A72),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 24,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 55,
              height: 3,
              decoration: BoxDecoration(
                color: _PayrollColors.blue,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayrollPanel extends StatelessWidget {
  const _PayrollPanel({
    required this.monthKey,
    required this.months,
    required this.employee,
    required this.status,
    required this.employees,
    required this.rows,
    required this.onMonthChanged,
    required this.onEmployeeChanged,
    required this.onStatusChanged,
    required this.onReset,
    required this.onMarkPaid,
    required this.onHistory,
    required this.onCycleOverride,
  });

  final String monthKey;
  final List<_MonthOption> months;
  final String employee, status;
  final List<String> employees;
  final List<_PayrollRow> rows;
  final ValueChanged<String?> onMonthChanged,
      onEmployeeChanged,
      onStatusChanged;
  final VoidCallback onReset;
  final ValueChanged<_PayrollRow> onMarkPaid;
  final ValueChanged<_PayrollRow> onHistory;
  final ValueChanged<_PayrollRow> onCycleOverride;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final palette = AdminSurfacePalette.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width < 600 ? 14 : 28,
        20,
        MediaQuery.sizeOf(context).width < 600 ? 14 : 28,
        18,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A071A72),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mobile)
            Text(
              'Payroll cycles',
              style: TextStyle(
                color: palette.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (!mobile) const SizedBox(height: 6),
          if (!mobile)
            Text(
              'Standard employees use the selected calendar month. Flexible employees use the cycle ending in the selected month; paid cycles remain in history.',
              style: TextStyle(color: palette.mutedText, fontSize: 13),
            ),
          SizedBox(height: mobile ? 0 : 16),
          _PayrollFilters(
            monthKey: monthKey,
            months: months,
            employee: employee,
            employees: employees,
            status: status,
            onMonthChanged: onMonthChanged,
            onEmployeeChanged: onEmployeeChanged,
            onStatusChanged: onStatusChanged,
            onReset: onReset,
          ),
          const SizedBox(height: 16),
          if (MediaQuery.sizeOf(context).width < 600)
            _MobilePayrollList(rows: rows, onMarkPaid: onMarkPaid)
          else
            _PayrollTable(
              rows: rows,
              onMarkPaid: onMarkPaid,
              onHistory: onHistory,
              onCycleOverride: onCycleOverride,
            ),
          const SizedBox(height: 16),
          Text(
            rows.isEmpty
                ? 'No payroll rows for these filters.'
                : 'Showing ${rows.length} employee${rows.length == 1 ? '' : 's'}',
            style: const TextStyle(color: Color(0xFF596176), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _PayrollFilters extends StatelessWidget {
  const _PayrollFilters({
    required this.monthKey,
    required this.months,
    required this.employee,
    required this.employees,
    required this.status,
    required this.onMonthChanged,
    required this.onEmployeeChanged,
    required this.onStatusChanged,
    required this.onReset,
  });

  final String monthKey;
  final List<_MonthOption> months;
  final String employee, status;
  final List<String> employees;
  final ValueChanged<String?> onMonthChanged,
      onEmployeeChanged,
      onStatusChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final monthValue = months.any((item) => item.key == monthKey)
        ? monthKey
        : (months.isEmpty ? monthKey : months.first.key);
    return LayoutBuilder(
      builder: (_, constraints) {
        final mobile = MediaQuery.sizeOf(context).width < 600;
        if (mobile) {
          return Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _showMobileFilters(context, monthValue),
                icon: const Icon(Icons.tune_rounded, size: 19),
                label: const Text('Filter'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _PayrollColors.blue,
                  side: const BorderSide(color: _PayrollColors.blue),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt_rounded),
                color: _PayrollColors.blue,
                tooltip: 'Reset filters',
              ),
            ],
          );
        }
        final width = constraints.maxWidth < 900 ? constraints.maxWidth : 280.0;
        return Wrap(
          spacing: 24,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _FilterField(
              label: 'Payroll ending month',
              width: width,
              child: DropdownButtonFormField<String>(
                initialValue: monthValue,
                onChanged: onMonthChanged,
                decoration: _fieldDecoration(),
                items:
                    (months.isEmpty
                            ? [
                                _MonthOption(
                                  year: DateTime.now().year,
                                  month: DateTime.now().month,
                                  label: 'This month',
                                ),
                              ]
                            : months)
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.key,
                            child: Text(item.label),
                          ),
                        )
                        .toList(),
              ),
            ),
            _FilterField(
              label: 'Employee',
              width: width,
              child: DropdownButtonFormField<String>(
                initialValue: employee,
                onChanged: onEmployeeChanged,
                decoration: _fieldDecoration(),
                items: employees
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
              ),
            ),
            _FilterField(
              label: 'Status',
              width: width,
              child: DropdownButtonFormField<String>(
                initialValue: status,
                onChanged: onStatusChanged,
                decoration: _fieldDecoration(),
                items: const ['All Status', 'Draft', 'Pending', 'Paid']
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reset'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _PayrollColors.blue,
                side: const BorderSide(color: Color(0xFFD6DDEA)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 17,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showMobileFilters(BuildContext context, String monthValue) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Filter payroll',
                style: TextStyle(
                  color: _PayrollColors.navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: monthValue,
                onChanged: onMonthChanged,
                decoration: _fieldDecoration().copyWith(
                  labelText: 'Payroll ending month',
                ),
                items: months
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.key,
                        child: Text(item.label),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: employee,
                onChanged: onEmployeeChanged,
                decoration: _fieldDecoration().copyWith(labelText: 'Employee'),
                items: employees
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                onChanged: onStatusChanged,
                decoration: _fieldDecoration().copyWith(labelText: 'Status'),
                items: const ['All Status', 'Draft', 'Pending', 'Paid']
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Apply filters'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.label,
    required this.width,
    required this.child,
  });
  final String label;
  final double width;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF596176), fontSize: 13),
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

InputDecoration _fieldDecoration() => InputDecoration(
  filled: true,
  fillColor: Colors.white,
  contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(7),
    borderSide: const BorderSide(color: Color(0xFFD8DEE9)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(7),
    borderSide: const BorderSide(color: _PayrollColors.blue),
  ),
);

class _MobilePayrollList extends StatelessWidget {
  const _MobilePayrollList({required this.rows, required this.onMarkPaid});
  final List<_PayrollRow> rows;
  final ValueChanged<_PayrollRow> onMarkPaid;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox(
        height: 140,
        child: Center(child: Text('No payroll rows match these filters.')),
      );
    }
    return Column(
      children: rows
          .map(
            (row) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE5EAF3)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFFEAF1FF),
                        child: Text(
                          row.name.isEmpty ? '?' : row.name.substring(0, 1),
                          style: const TextStyle(
                            color: _PayrollColors.blue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.name,
                              style: const TextStyle(
                                color: _PayrollColors.navy,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${row.code} • ${row.department}',
                              style: const TextStyle(
                                color: Color(0xFF657087),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _PayStatus(status: row.status),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Salary ${row.salary}  →  Net ${row.netPay}',
                    style: const TextStyle(
                      color: _PayrollColors.navy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Paid ${row.paidDays}/${row.workingDays} days • LOP ${row.lopDays}',
                    style: const TextStyle(
                      color: Color(0xFF657087),
                      fontSize: 12,
                    ),
                  ),
                  if (row.status == 'Pending') ...[
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: () => onMarkPaid(row),
                      style: FilledButton.styleFrom(
                        backgroundColor: _PayrollColors.blue,
                      ),
                      child: const Text('Mark paid'),
                    ),
                  ],
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _PayrollTable extends StatelessWidget {
  const _PayrollTable({
    required this.rows,
    required this.onMarkPaid,
    required this.onHistory,
    required this.onCycleOverride,
  });
  final List<_PayrollRow> rows;
  final ValueChanged<_PayrollRow> onMarkPaid;
  final ValueChanged<_PayrollRow> onHistory;
  final ValueChanged<_PayrollRow> onCycleOverride;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Keep every payroll column in the current frame. The container border
      // consumes two pixels, and enlarging beyond the natural table width can
      // force the final Action cell outside the frame. Only shrink when needed.
      final availableWidth = constraints.maxWidth - 2;
      final scale = (availableWidth / _PayrollTableHeader.naturalWidth)
          .clamp(0.45, 1.0)
          .toDouble();
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE3E7EF)),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _PayrollTableHeader(scale: scale),
            if (rows.isEmpty)
              const SizedBox(
                height: 160,
                child: Center(
                  child: Text('No payroll rows match these filters.'),
                ),
              )
            else
              ...rows.map(
                (row) => _PayrollTableRow(
                  row: row,
                  scale: scale,
                  onMarkPaid: onMarkPaid,
                  onHistory: onHistory,
                  onCycleOverride: onCycleOverride,
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _PayrollTableHeader extends StatelessWidget {
  const _PayrollTableHeader({required this.scale});
  static const naturalWidth = 1650.0;
  final double scale;
  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    color: AdminSurfacePalette.of(context).subtleSurface,
    child: Row(
      children: [
        _Cell(width: 250 * scale, child: Text('Employee', style: _headStyle)),
        _Cell(width: 150 * scale, child: Text('Department', style: _headStyle)),
        _Cell(width: 140 * scale, child: Text('Monthly salary', style: _headStyle)),
        _Cell(width: 110 * scale, child: Text('Working', style: _headStyle)),
        _Cell(width: 110 * scale, child: Text('Paid days', style: _headStyle)),
        _Cell(width: 90 * scale, child: Text('LOP', style: _headStyle)),
        _Cell(width: 130 * scale, child: Text('Late\nDeduction', style: _headStyle)),
        _Cell(width: 140 * scale, child: Text('Absent / LOP\nValue', style: _headStyle)),
        _Cell(width: 130 * scale, child: Text('Total\nDeduction', style: _headStyle)),
        _Cell(width: 140 * scale, child: Text('Net pay', style: _headStyle)),
        _Cell(width: 120 * scale, child: Text('Status', style: _headStyle)),
        _Cell(width: 140 * scale, child: Text('Action', style: _headStyle)),
      ],
    ),
  );
}

class _PayrollTableRow extends StatelessWidget {
  const _PayrollTableRow({
    required this.row,
    required this.scale,
    required this.onMarkPaid,
    required this.onHistory,
    required this.onCycleOverride,
  });
  final _PayrollRow row;
  final double scale;
  final ValueChanged<_PayrollRow> onMarkPaid;
  final ValueChanged<_PayrollRow> onHistory;
  final ValueChanged<_PayrollRow> onCycleOverride;

  @override
  Widget build(BuildContext context) => Container(
    height: 72,
    decoration: BoxDecoration(
      color: AdminSurfacePalette.of(context).surface,
      border: Border(top: BorderSide(color: AdminSurfacePalette.of(context).border)),
    ),
    child: Row(
      children: [
        _Cell(
          width: 250 * scale,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFE8EEF8),
                child: Text(
                  row.name.isEmpty ? '?' : row.name.substring(0, 1),
                  style: const TextStyle(
                    color: _PayrollColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF11131A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      row.salaryType == 'Flexible' && row.periodStart.isNotEmpty
                          ? '${row.code} • ${row.periodStart} – ${row.periodEnd}'
                          : row.code,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF596176),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _Cell(width: 150 * scale, child: Text(row.department, style: _cellStyle)),
        _Cell(width: 140 * scale, child: Text(row.salary, style: _cellStyle)),
        _Cell(width: 110 * scale, child: Text('${row.workingDays}', style: _cellStyle)),
        _Cell(width: 110 * scale, child: Text('${row.paidDays}', style: _cellStyle)),
        _Cell(width: 90 * scale, child: Text('${row.lopDays}', style: _cellStyle)),
        _Cell(width: 130 * scale, child: Text(row.lateDeduction, style: _cellStyle)),
        _Cell(width: 140 * scale, child: Text(row.absentDeduction, style: _cellStyle)),
        _Cell(width: 130 * scale, child: Text(row.totalDeduction, style: _cellStyle)),
        _Cell(
          width: 140 * scale,
          child: Text(
            row.netPay,
            style: const TextStyle(
              color: _PayrollColors.navy,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        _Cell(width: 120 * scale, child: _PayStatus(status: row.status)),
        _Cell(
          width: 140 * scale,
          child: PopupMenuButton<int>(
            tooltip: 'Payroll actions',
            onSelected: (action) {
              if (action == 0) onHistory(row);
              if (action == 1) onCycleOverride(row);
              if (action == 2) onMarkPaid(row);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 0,
                child: ListTile(
                  leading: Icon(Icons.history_outlined),
                  title: Text('View history'),
                ),
              ),
              if (row.salaryType == 'Flexible' && row.status != 'Paid')
                const PopupMenuItem(
                  value: 1,
                  child: ListTile(
                    leading: Icon(Icons.date_range_outlined),
                    title: Text('Custom cycle'),
                  ),
                ),
              if (row.status == 'Pending')
                const PopupMenuItem(
                  value: 2,
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('Mark paid'),
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD8DEE9)),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.more_horiz_rounded,
                    size: 18,
                    color: _PayrollColors.blue,
                  ),
                  SizedBox(width: 5),
                  Text(
                    'Actions',
                    style: TextStyle(
                      color: _PayrollColors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Cell extends StatelessWidget {
  const _Cell({required this.width, required this.child});
  final double width;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: child,
    ),
  );
}

class _PayStatus extends StatelessWidget {
  const _PayStatus({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = status == 'Paid'
        ? const Color(0xFF188226)
        : status == 'Pending'
        ? const Color(0xFFFF6500)
        : const Color(0xFF596176);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(status, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

class _PayrollRow {
  const _PayrollRow({
    required this.itemId,
    required this.profileId,
    required this.name,
    required this.code,
    required this.department,
    required this.salary,
    required this.workingDays,
    required this.paidDays,
    required this.lopDays,
    required this.lateDeduction,
    required this.absentDeduction,
    required this.totalDeduction,
    required this.netPay,
    required this.status,
    required this.salaryType,
    required this.periodStart,
    required this.periodEnd,
  });

  final int? itemId;
  final int profileId;
  final String name, code, department, salary, lateDeduction, absentDeduction,
      totalDeduction, netPay, status;
  final int workingDays, paidDays, lopDays;
  final String salaryType, periodStart, periodEnd;

  factory _PayrollRow.fromApi(Map<String, dynamic> json) {
    int asInt(dynamic value) =>
        value is int ? value : int.tryParse('$value') ?? 0;
    final rawId = json['id'];
    String money(dynamic value) {
      final amount = value is num ? value : num.tryParse('$value');
      if (amount == null) return '–';
      return '₹${amount.round()}';
    }
    final lateDeduction = json['lateDeductions'] ?? json['deductions'] ?? 0;
    final absentDeduction = json['absentDeductions'] ?? 0;
    final totalDeduction =
        (lateDeduction is num ? lateDeduction : num.tryParse('$lateDeduction') ?? 0) +
        (absentDeduction is num
            ? absentDeduction
            : num.tryParse('$absentDeduction') ?? 0);
    return _PayrollRow(
      itemId: rawId == null ? null : asInt(rawId),
      profileId: asInt(json['profileId']),
      name: (json['name'] ?? '').toString(),
      code: (json['employeeCode'] ?? '').toString(),
      department: (json['department'] ?? '').toString(),
      salary: (json['salary'] ?? 'Not Set').toString(),
      workingDays: asInt(json['workingDays']),
      paidDays: asInt(json['paidDays']),
      lopDays: asInt(json['lopDays']),
      lateDeduction: money(lateDeduction),
      absentDeduction: money(absentDeduction),
      totalDeduction: money(totalDeduction),
      netPay: (json['netPayLabel'] ?? '–').toString(),
      status: (json['status'] ?? 'Draft').toString(),
      salaryType: (json['salaryType'] ?? 'Standard').toString(),
      periodStart: (json['periodStart'] ?? '').toString(),
      periodEnd: (json['periodEnd'] ?? '').toString(),
    );
  }
}

const _headStyle = TextStyle(
  color: Color(0xFF11131A),
  fontSize: 13,
  fontWeight: FontWeight.w600,
);
const _cellStyle = TextStyle(color: Color(0xFF272B35), fontSize: 13);
