import 'package:flutter/material.dart';
import '../../services/hrms_payslip_api.dart';

import '../shared/employee_ui.dart';

class EmployeeSalaryPage extends StatelessWidget {
  const EmployeeSalaryPage({super.key});

  @override
  Widget build(BuildContext context) => const EmployeeScaffold(
        route: '/employee/salary',
        title: 'Salary',
        subtitle: 'Payslips and salary details',
        desktop: _SalaryView(mobile: false, showPayslip: true),
        mobile: _SalaryView(mobile: true, showPayslip: true),
      );
}

class _SalaryView extends StatelessWidget {
  const _SalaryView({required this.mobile, required this.showPayslip});
  final bool mobile;
  final bool showPayslip;

  static void openPayslipSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, 4, 22, 28),
          child: SingleChildScrollView(child: _RecentPayslipsCard()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewButton =
        _ViewPayslipButton(
          onPressed: () => _showPayrollHistory(context),
        );

    if (mobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const MobileEmployeeHeader(showGreeting: false),
        const SizedBox(height: 22),
        const Text('Payslips and salary details',
            style: TextStyle(color: employeeMuted, fontSize: 18)),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Expanded(
            child: Text('Salary',
                style: TextStyle(
                    color: employeeNavy,
                    fontSize: 34,
                    height: 1,
                    fontWeight: FontWeight.w800)),
          ),
          viewButton,
        ]),
        const SizedBox(height: 18),
        const _NetPayBanner(mobile: true),
        const SizedBox(height: 16),
        const _SalaryOverviewCard(),
        const SizedBox(height: 16),
        const _RecentPayslipsCard(),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            'Payslips are available for download after payroll processing.',
            textAlign: TextAlign.center,
            style: TextStyle(color: employeeMuted, fontSize: 12),
          ),
        ),
      ]);
    }

    if (!showPayslip) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [viewButton],
      ),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Expanded(child: _NetPayBanner(mobile: false)),
          SizedBox(width: 20),
          Expanded(child: _SalaryOverviewCard()),
        ]),
      const SizedBox(height: 20),
      const _RecentPayslipsCard(),
      const SizedBox(height: 14),
      const Center(
        child: Text(
          'Payslips are available for download after payroll processing.',
          style: TextStyle(color: employeeMuted, fontSize: 12),
        ),
      ),
    ]);
  }
}

class _ViewPayslipButton extends StatelessWidget {
  const _ViewPayslipButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.history_outlined, size: 21),
        label: const Text('View history',
            style: TextStyle(fontWeight: FontWeight.w700)),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF052D70),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
}

String _money(dynamic value) => '₹${(num.tryParse('$value') ?? 0).toStringAsFixed(0)}';
Map<String, dynamic> _dataMap(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : const {};
double _amount(dynamic value) => num.tryParse('$value')?.toDouble() ?? 0;

class _NetPayBanner extends StatefulWidget {
  const _NetPayBanner({required this.mobile});
  final bool mobile;
  @override State<_NetPayBanner> createState() => _NetPayBannerState();
}
class _NetPayBannerState extends State<_NetPayBanner> {
  late final Future<Map<String, dynamic>> _data = HrmsPayslipApi.summary();

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(future: _data, builder: (context, snapshot) {
    final payroll = _dataMap(snapshot.data?['payroll']);
    final paid = payroll['status'] == 'paid';
    final updatedSalary = _amount(payroll['net_pay'] ?? payroll['updated_salary'] ?? payroll['monthly_salary']);
    return Container(
        constraints: BoxConstraints(minHeight: widget.mobile ? 190 : 285),
        padding: EdgeInsets.all(widget.mobile ? 22 : 34),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF063B82), Color(0xFF031C54)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26002061),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Updated Salary',
                    style: TextStyle(
                        color: Colors.white, fontSize: widget.mobile ? 18 : 22)),
                const SizedBox(height: 10),
                if (payroll.isEmpty)
                  Text(snapshot.data?['reviewRequired'] == true ? 'Payroll under review' : 'Payroll not generated', style: TextStyle(color: Colors.white, fontSize: widget.mobile ? 22 : 28, fontWeight: FontWeight.w700))
                else ...[
                  Text(_money(updatedSalary), maxLines: 1, style: TextStyle(color: Colors.white, fontSize: widget.mobile ? 38 : 50, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('Earned to Date: ${_money(updatedSalary)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('${payroll['pay_month']}/${payroll['pay_year']}',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: widget.mobile ? 18 : 21,
                        fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 13),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF005A43),
                    border: Border.all(color: const Color(0xFF008F63)),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(radius: 5, backgroundColor: paid ? const Color(0xFF1DDA83) : const Color(0xFFB7C6DF)),
                    const SizedBox(width: 8),
                    Text(paid ? 'PAID' : 'UPDATES DAILY', style: TextStyle(color: paid ? const Color(0xFF2DE38E) : const Color(0xFFD6E0EF), fontWeight: FontWeight.w700)),
                  ]),
                ),
              ],
            ),
          ),
          SizedBox(width: widget.mobile ? 8 : 24),
          _WalletArtwork(size: widget.mobile ? 118 : 190),
        ]),
      );
  });
}

class _WalletArtwork extends StatelessWidget {
  const _WalletArtwork({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0x1F61A8FF),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x33489EFF)),
            ),
          ),
          Icon(Icons.account_balance_wallet_rounded,
              color: const Color(0xFF9DBDE8), size: size * .56),
          Positioned(
            top: size * .10,
            right: size * .30,
            child: _Coin(size: size * .27),
          ),
          Positioned(
            top: size * .38,
            right: size * .02,
            child: _Coin(size: size * .25),
          ),
        ]),
      );
}

class _Coin extends StatelessWidget {
  const _Coin({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF789FD3),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFAEC7E8)),
        ),
        child: Text('₹',
            style: TextStyle(
                color: const Color(0xFF315C98),
                fontSize: size * .48,
                fontWeight: FontWeight.w800)),
      );
}

class _SalaryOverviewCard extends StatefulWidget {
  const _SalaryOverviewCard();
  @override State<_SalaryOverviewCard> createState() => _SalaryOverviewCardState();
}

String _monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

Future<void> _showPayrollHistory(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _PayrollHistoryDialog(),
  );
}

class _PayrollHistoryDialog extends StatefulWidget {
  const _PayrollHistoryDialog();
  @override State<_PayrollHistoryDialog> createState() => _PayrollHistoryDialogState();
}

class _PayrollHistoryDialogState extends State<_PayrollHistoryDialog> {
  late String _month = _monthKey(DateTime.now());
  late Future<Map<String, dynamic>> _future = HrmsPayslipApi.history(_month);

  List<String> get _months => List.generate(12, (i) {
        final d = DateTime(DateTime.now().year, DateTime.now().month - i, 1);
        return _monthKey(d);
      });

  String _displayMonth(String key) {
    final p = key.split('-');
    final d = DateTime(int.parse(p[0]), int.parse(p[1]), 1);
    const names = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${names[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 42, vertical: 28),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1750, maxHeight: 820),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              final payload = snapshot.data ?? const <String, dynamic>{};
              final summary = _dataMap(payload['summary']);
              final rawItems = payload['items'];
              final items = rawItems is List
                  ? rawItems.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
                  : <Map<String, dynamic>>[];
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(30, 24, 18, 18),
                  child: Row(children: [
                    const Expanded(child: Text('Payroll history', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: employeeNavy))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: employeeLine))),
                      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                        value: _month,
                        icon: const Icon(Icons.arrow_drop_down_rounded, color: employeeMuted),
                        items: _months.map((m) => DropdownMenuItem(value: m, child: Text(_displayMonth(m), style: const TextStyle(color: employeeNavy, fontWeight: FontWeight.w600)))).toList(),
                        onChanged: (v) { if (v == null) return; setState(() { _month = v; _future = HrmsPayslipApi.history(v); }); },
                      )),
                    ),
                    const SizedBox(width: 12),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: employeeMuted, size: 28)),
                  ]),
                ),
                Container(height: 1, color: employeeLine),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
                  child: Wrap(spacing: 10, runSpacing: 10, children: [
                    _PayrollHeaderChip(label: 'Total salary', value: _ledgerMoney(summary['monthly_salary'])),
                    _PayrollHeaderChip(label: 'Working days', value: '${_amount(summary['working_days']).toStringAsFixed(0)}'),
                    _PayrollHeaderChip(label: 'Paid days', value: '${_amount(summary['paid_days']).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}'),
                    _PayrollHeaderChip(label: 'LOP', value: '${_amount(summary['lop_days']).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}', valueColor: const Color(0xFFD93445)),
                    _PayrollHeaderChip(label: 'Net pay', value: _ledgerMoney(summary['net_pay']), valueColor: employeeBlue),
                  ]),
                ),
                Container(height: 1, color: employeeLine),
                Expanded(child: Builder(builder: (context) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(30), child: Text('Unable to load payroll history.', style: TextStyle(color: employeeMuted))));
                  if (items.isEmpty) return const Center(child: Text('No payroll days are available for this period.', style: TextStyle(color: employeeMuted)));
                  return _PayrollLedgerTable(items: items);
                })),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 30, 18),
                  child: Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))),
                ),
              ]);
            },
          ),
        ),
      );
}

String _ledgerMoney(dynamic value) {
  final amount = _amount(value);
  return amount == amount.roundToDouble() ? '₹${amount.toStringAsFixed(0)}' : '₹${amount.toStringAsFixed(2)}';
}

class _PayrollHeaderChip extends StatelessWidget {
  const _PayrollHeaderChip({required this.label, required this.value, this.valueColor = employeeNavy});
  final String label;
  final String value;
  final Color valueColor;
  @override
  Widget build(BuildContext context) => Container(
    width: 138,
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(color: const Color(0xFFF4F7FD), border: Border.all(color: employeeLine), borderRadius: BorderRadius.circular(10)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: employeeMuted, fontSize: 11)),
      const SizedBox(height: 3),
      Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.w800, fontSize: 15)),
    ]),
  );
}

class _PayrollLedgerTable extends StatelessWidget {
  const _PayrollLedgerTable({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) => Scrollbar(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 16, 30, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1450),
          child: Column(children: [
            const _PayrollLedgerRow(header: true),
            ...items.map((item) => _PayrollLedgerRow(item: item)),
          ]),
        ),
      ),
    ),
  );
}

class _PayrollLedgerRow extends StatelessWidget {
  const _PayrollLedgerRow({this.item, this.header = false});
  final Map<String, dynamic>? item;
  final bool header;
  static const _widths = [150.0, 125.0, 112.0, 145.0, 145.0, 135.0, 170.0, 150.0, 155.0, 155.0, 150.0];
  static const _labels = ['Date', 'Salary', 'Working', 'Check in', 'Check out', 'Status', 'Late deduction time', 'Late deduction', 'Absent / LOP', 'Total deduction', 'Present amount'];

  @override
  Widget build(BuildContext context) {
    if (header) return Container(
      height: 46,
      decoration: BoxDecoration(color: const Color(0xFFF4F7FD), borderRadius: BorderRadius.circular(9)),
      child: Row(children: List.generate(_labels.length, (i) => _PayrollLedgerCell(width: _widths[i], value: _labels[i], header: true))),
    );
    final row = item!;
    final status = '${row['status'] ?? '—'}';
    final lateMinutes = _amount(row['late_minutes']).toStringAsFixed(0);
    return Container(
      height: 60,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: employeeLine))),
      child: Row(children: [
        _PayrollLedgerCell(width: _widths[0], value: _ledgerDate(row['date'])),
        _PayrollLedgerCell(width: _widths[1], value: _ledgerMoney(row['salary'])),
        _PayrollLedgerCell(width: _widths[2], value: _amount(row['working']).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')),
        _PayrollLedgerCell(width: _widths[3], value: _payrollTime(row['check_in'])),
        _PayrollLedgerCell(width: _widths[4], value: _payrollTime(row['check_out'])),
        _PayrollLedgerCell(width: _widths[5], child: _PayrollStatus(status: status)),
        _PayrollLedgerCell(width: _widths[6], value: lateMinutes == '0' ? '—' : '$lateMinutes min'),
        _PayrollLedgerCell(width: _widths[7], value: _ledgerMoney(row['late_deduction']), color: const Color(0xFFE06E00)),
        _PayrollLedgerCell(width: _widths[8], value: _ledgerMoney(row['absent_deduction']), color: const Color(0xFFD93445)),
        _PayrollLedgerCell(width: _widths[9], value: _ledgerMoney(row['total_deduction']), color: const Color(0xFFD93445)),
        _PayrollLedgerCell(width: _widths[10], value: _ledgerMoney(row['present_amount']), color: const Color(0xFF008944)),
      ]),
    );
  }
}

class _PayrollLedgerCell extends StatelessWidget {
  const _PayrollLedgerCell({required this.width, this.value, this.child, this.header = false, this.color = employeeNavy});
  final double width;
  final String? value;
  final Widget? child;
  final bool header;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(width: width, child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Align(alignment: Alignment.centerLeft, child: child ?? Text(value ?? '—', overflow: TextOverflow.ellipsis, style: TextStyle(color: header ? employeeMuted : color, fontSize: header ? 13 : 14, fontWeight: header ? FontWeight.w700 : FontWeight.w500))),
  ));
}

class _PayrollStatus extends StatelessWidget {
  const _PayrollStatus({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final value = status.toLowerCase();
    final present = value.contains('present') || value.contains('late');
    final absent = value.contains('absent') || value.contains('lop');
    final color = present ? const Color(0xFF008944) : absent ? const Color(0xFFD93445) : employeeMuted;
    final bg = present ? const Color(0xFFE1F8EA) : absent ? const Color(0xFFFFE8EA) : const Color(0xFFF0F3F8);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)), child: Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)));
  }
}

String _ledgerDate(dynamic value) {
  final raw = '$value';
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  const shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${date.day.toString().padLeft(2, '0')} ${shortMonths[date.month - 1]}, ${weekdays[date.weekday - 1]}';
}

String _payrollTime(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty || raw == '-' || raw == '—') return '—';
  final dateTime = DateTime.tryParse(raw);
  if (dateTime == null) return raw;
  final local = dateTime.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

Future<void> _showDeductionHistory(BuildContext context) async {
  try {
    final items = await HrmsPayslipApi.deductionHistory();
    if (!context.mounted) return;
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Deduction history'),
      content: SizedBox(width: 520, child: items.isEmpty
          ? const Text('No late or absent deductions in the current payroll cycle.')
          : SingleChildScrollView(child: DataTable(columns: const [DataColumn(label: Text('Date')), DataColumn(label: Text('Type')), DataColumn(label: Text('Late')), DataColumn(label: Text('Amount'))], rows: items.map((item) => DataRow(cells: [DataCell(Text('${item['attendance_date']}')), DataCell(Text('${item['deduction_type']}' == 'late' ? 'Late' : 'Absent')), DataCell(Text('${item['late_minutes'] ?? 0} min')), DataCell(Text('₹${item['amount']}'))])).toList()))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
    ));
  } catch (error) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')))); }
}
class _SalaryOverviewCardState extends State<_SalaryOverviewCard> {
  late final Future<Map<String, dynamic>> _data = HrmsPayslipApi.summary();

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(future: _data, builder: (context, snapshot) {
    final payroll = _dataMap(snapshot.data?['payroll']);
    final monthlySalary = _amount(payroll['monthly_salary']);
    final workingDays = _amount(payroll['working_days']);
    final paidDays = _amount(payroll['paid_days']);
    final lateDeduction = _amount(payroll['late_deductions']);
    final absenceDeduction = _amount(payroll['absent_deductions'] ?? payroll['deductions']);
    final totalDeduction = lateDeduction + absenceDeduction;
    final deductionDays = _amount(payroll['lop_days']);
    final updatedSalary = _amount(payroll['net_pay'] ?? payroll['updated_salary'] ?? payroll['monthly_salary']);
    return SizedBox(width: double.infinity, child: EmployeeCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SalaryHeading('Salary Overview'), const SizedBox(height: 16),
          if (payroll.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(snapshot.data?['reviewRequired'] == true ? 'Admin needs to correct an existing payroll record before salary payment details can be shown.' : 'Payroll has not been generated for this employee.', style: const TextStyle(color: employeeMuted))) else ...[
            Row(children: [
              Expanded(child: _OverviewMetric(label: 'Salary / Month', value: _money(monthlySalary))),
              const _OverviewDivider(),
              Expanded(child: _OverviewMetric(label: 'Deduction', value: totalDeduction > 0 ? '−${_money(totalDeduction)} / ${deductionDays.toStringAsFixed(0)} ${deductionDays == 1 ? 'day' : 'days'}' : '₹0')),
              const _OverviewDivider(),
              Expanded(child: Container(padding: const EdgeInsets.all(12), color: const Color(0xFFF0F6FF), child: _OverviewMetric(label: 'Updated Salary', value: _money(updatedSalary), valueColor: employeeBlue))),
            ]),
            const SizedBox(height: 14), const Divider(height: 1, color: employeeLine),
            LabeledValue('Total Working Days', workingDays.toStringAsFixed(0)), const Divider(height: 1, color: employeeLine),
            LabeledValue('Earned to Date', '${_money(updatedSalary)} / ${paidDays.toStringAsFixed(0)} ${paidDays == 1 ? 'day' : 'days'}'),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: () => _showDeductionHistory(context), icon: const Icon(Icons.history_outlined), label: const Text('View deduction history')),
          ],
        ]),
      ));
  });
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.label, required this.value, this.valueColor = employeeNavy});
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: employeeMuted, fontSize: 11)),
    const SizedBox(height: 7),
    Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: valueColor, fontSize: 15, fontWeight: FontWeight.w800)),
  ]);
}

class _OverviewDivider extends StatelessWidget {
  const _OverviewDivider();
  @override
  Widget build(BuildContext context) => const SizedBox(height: 62, child: VerticalDivider(width: 24, color: employeeLine));
}

class _SalaryBreakdownCard extends StatefulWidget {
  const _SalaryBreakdownCard();
  @override State<_SalaryBreakdownCard> createState() => _SalaryBreakdownCardState();
}
class _SalaryBreakdownCardState extends State<_SalaryBreakdownCard> {
  late final Future<Map<String, dynamic>> _data = HrmsPayslipApi.summary();

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(future: _data, builder: (context, snapshot) {
    final compensation = _dataMap(snapshot.data?['compensation']);
    final payroll = _dataMap(snapshot.data?['payroll']);
    return SizedBox(width: double.infinity, child: EmployeeCard(
        padding: EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SalaryHeading('Salary Breakdown'), const SizedBox(height: 10),
          if (compensation.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Salary not configured. Contact Admin to set your compensation.', style: TextStyle(color: employeeMuted)))
          else if (payroll.isEmpty) ...[
            LabeledValue('Monthly Salary', _money(compensation['monthly_salary'])),
            const Divider(height: 1, color: employeeLine),
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(snapshot.data?['reviewRequired'] == true ? 'Payroll correction required.' : 'Payroll not generated yet.', style: const TextStyle(color: employeeMuted))),
          ] else ...[
            LabeledValue('Monthly Salary', _money(payroll['monthly_salary'])), const Divider(height: 1, color: employeeLine),
            LabeledValue('Late Deduction', '−${_money(payroll['late_deductions'] ?? 0)}'), const Divider(height: 1, color: employeeLine),
            LabeledValue('Absent / Leave Deduction', '−${_money(payroll['absent_deductions'] ?? payroll['deductions'])}'),
          ],
        ]),
      ));
  });
}

class _SalaryHeading extends StatelessWidget {
  const _SalaryHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: employeeNavy, fontSize: 20, fontWeight: FontWeight.w800));
}

class _RecentPayslipsCard extends StatefulWidget {
  const _RecentPayslipsCard();
  @override
  State<_RecentPayslipsCard> createState() => _RecentPayslipsCardState();
}

class _RecentPayslipsCardState extends State<_RecentPayslipsCard> {
  late Future<List<Map<String, dynamic>>> _items = HrmsPayslipApi.mine();
  void _refresh() {
    final next = HrmsPayslipApi.mine();
    if (!mounted) return;
    setState(() {
      _items = next;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _items,
    builder: (context, snapshot) => SizedBox(width: double.infinity, child: EmployeeCard(
        padding: EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SalaryHeading('Recent Payslips'),
          SizedBox(height: 10),
          if (snapshot.connectionState != ConnectionState.done) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (snapshot.hasError) const Padding(padding: EdgeInsets.all(16), child: Text('Unable to load payslips', style: TextStyle(color: employeeMuted)))
          else if ((snapshot.data ?? const <Map<String, dynamic>>[]).isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No paid payslips are available yet.', style: TextStyle(color: employeeMuted)))
          else ...((snapshot.data ?? const <Map<String, dynamic>>[]).take(3).map((item) => _LivePayslipRow(item: item, onChanged: _refresh))),
        ]),
      )));
}

class _LivePayslipRow extends StatefulWidget {
  const _LivePayslipRow({required this.item, required this.onChanged});
  final Map<String, dynamic> item;
  final VoidCallback onChanged;
  @override State<_LivePayslipRow> createState() => _LivePayslipRowState();
}
class _LivePayslipRowState extends State<_LivePayslipRow> {
  bool busy = false;
  String get status => '${widget.item['request_status']}';
  String get month => '${widget.item['pay_month']}/${widget.item['pay_year']}';
  Future<void> download(BuildContext context) async {
    if (status == 'not_requested') {
      final confirm = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(title: const Text('Send payslip request?'), content: const Text('Send this download request to Admin for approval?'), actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Send request'))]));
      if (confirm != true || !mounted || !context.mounted) return;
    }
    setState(() => busy = true);
    try {
      if (status == 'approved') { await HrmsPayslipApi.download(int.parse('${widget.item['id']}')); if (!context.mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payslip download started.'))); }
      else if (status == 'not_requested') { await HrmsPayslipApi.request(int.parse('${widget.item['id']}')); widget.onChanged(); }
      else { if (!context.mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status == 'rejected' ? 'Your request was rejected.' : 'Your request is awaiting Admin approval.'))); }
    } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(month, style: const TextStyle(color: employeeNavy, fontWeight: FontWeight.w800)), Text(status == 'approved' ? 'Approved for download' : status == 'pending' ? 'Approval pending' : status == 'rejected' ? 'Request rejected' : 'Request download approval', style: const TextStyle(color: employeeMuted, fontSize: 12))])), Text('₹${widget.item['net_pay']}', style: const TextStyle(color: employeeNavy, fontWeight: FontWeight.w700)), const SizedBox(width: 7), IconButton(tooltip: status == 'approved' ? 'Download payslip' : 'Request payslip', onPressed: busy ? null : () => download(context), icon: Icon(Icons.download_rounded, color: status == 'approved' ? const Color(0xFF158C20) : employeeBlue))]));
}
