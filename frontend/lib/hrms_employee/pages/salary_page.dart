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
        const _SalaryBreakdownCard(),
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
          Expanded(flex: 6, child: _NetPayBanner(mobile: false)),
          SizedBox(width: 20),
          Expanded(
            flex: 5,
            child: Column(children: [
              _SalaryOverviewCard(),
              SizedBox(height: 18),
              _SalaryBreakdownCard(),
            ]),
          ),
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
                Text('Net Pay',
                    style: TextStyle(
                        color: Colors.white, fontSize: widget.mobile ? 18 : 22)),
                const SizedBox(height: 10),
                if (payroll.isEmpty)
                  Text(snapshot.data?['reviewRequired'] == true ? 'Payroll under review' : 'Payroll not generated', style: TextStyle(color: Colors.white, fontSize: widget.mobile ? 22 : 28, fontWeight: FontWeight.w700))
                else ...[
                  Text(_money(payroll['net_pay'] ?? payroll['updated_salary'] ?? payroll['monthly_salary']), maxLines: 1, style: TextStyle(color: Colors.white, fontSize: widget.mobile ? 38 : 50, fontWeight: FontWeight.w800)),
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
                    Text(paid ? 'PAID' : 'PENDING', style: TextStyle(color: paid ? const Color(0xFF2DE38E) : const Color(0xFFD6E0EF), fontWeight: FontWeight.w700)),
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
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Expanded(child: Text('Payroll history', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: employeeNavy))),
                DropdownButton<String>(value: _month, items: _months.map((m) => DropdownMenuItem(value: m, child: Text(_displayMonth(m)))).toList(), onChanged: (v) { if (v == null) return; setState(() { _month = v; _future = HrmsPayslipApi.history(v); }); }),
                const SizedBox(width: 12), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 16),
              Expanded(child: FutureBuilder<Map<String, dynamic>>(future: _future, builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Text('Unable to load payroll history: ${snapshot.error}', style: const TextStyle(color: employeeMuted)));
                final rawItems = snapshot.data?['items'];
                final items = rawItems is List
                    ? rawItems.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
                    : <Map<String, dynamic>>[];
                if (items.isEmpty) return const Center(child: Text('No payroll or attendance records for this month.', style: TextStyle(color: employeeMuted)));
                return Scrollbar(child: SingleChildScrollView(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [
                  DataColumn(label: Text('Date')), DataColumn(label: Text('Salary')), DataColumn(label: Text('Working')), DataColumn(label: Text('Check-in')), DataColumn(label: Text('Check-out')), DataColumn(label: Text('Status')), DataColumn(label: Text('Late deduction')), DataColumn(label: Text('Absent/LOP')), DataColumn(label: Text('Total deduction')), DataColumn(label: Text('Updated salary')),
                ], rows: items.map((r) => DataRow(cells: [
                  DataCell(Text('${r['date'] ?? '-'}')), DataCell(Text(_money(r['salary']))), DataCell(Text('${r['working'] ?? 0}')), DataCell(Text(_payrollTime(r['check_in']))), DataCell(Text(_payrollTime(r['check_out']))), DataCell(Text('${r['status'] ?? '-'}')), DataCell(Text(_money(r['late_deduction']))), DataCell(Text(_money(r['absent_deduction']))), DataCell(Text(_money(r['total_deduction']))), DataCell(Text(_money(r['updated_salary']))),
                ])).toList()))));
              })),
            ]),
          ),
        ),
      );
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
    return SizedBox(width: double.infinity, child: EmployeeCard(
        padding: EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SalaryHeading('Salary Overview'), const SizedBox(height: 10),
          if (payroll.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(snapshot.data?['reviewRequired'] == true ? 'Admin needs to correct an existing payroll record before salary payment details can be shown.' : 'Payroll has not been generated for this employee.', style: const TextStyle(color: employeeMuted))) else ...[
            LabeledValue('Gross Salary', _money(payroll['monthly_salary'])), const Divider(height: 1, color: employeeLine),
            LabeledValue('Late Deduction', '−${_money(payroll['late_deductions'] ?? 0)}'), const Divider(height: 1, color: employeeLine),
            LabeledValue('Absent / Leave Deduction', '−${_money(payroll['absent_deductions'] ?? payroll['deductions'])}'), const Divider(height: 1, color: employeeLine),
            LabeledValue('Net Pay', _money(payroll['net_pay'] ?? payroll['updated_salary'] ?? payroll['monthly_salary']), valueColor: employeeBlue),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () => _showDeductionHistory(context), icon: const Icon(Icons.history_outlined), label: const Text('View deduction history')),
          ],
        ]),
      ));
  });
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
