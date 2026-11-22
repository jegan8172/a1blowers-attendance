import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  @override
  Widget build(BuildContext context) {
    final viewButton = _ViewPayslipButton(
      onPressed: () => _showPayrollHistory(context),
    );

    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payslips and salary details',
                      style: GoogleFonts.inter(
                        color: employeeMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Salary',
                      style: GoogleFonts.inter(
                        color: employeeNavy,
                        fontSize: 31,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.9,
                      ),
                    ),
                  ],
                ),
              ),
              _PremiumHistoryButton(
                onPressed: () => _showPayrollHistory(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _NetPayBanner(mobile: true),
          const SizedBox(height: 14),
          const _SalaryOverviewCard(),
          const SizedBox(height: 14),
          const _RecentPayslipsCard(),
        ],
      );
    }

    if (!showPayslip) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [viewButton]),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Expanded(child: _NetPayBanner(mobile: false)),
            SizedBox(width: 20),
            Expanded(child: _SalaryOverviewCard()),
          ],
        ),
        const SizedBox(height: 20),
        const _RecentPayslipsCard(),
        const SizedBox(height: 14),
        const Center(
          child: Text(
            'Payslips are available for download after payroll processing.',
            style: TextStyle(color: employeeMuted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _ViewPayslipButton extends StatelessWidget {
  const _ViewPayslipButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.history_outlined, size: 21),
    label: const Text(
      'View history',
      style: TextStyle(fontWeight: FontWeight.w700),
    ),
    style: FilledButton.styleFrom(
      backgroundColor: const Color(0xFF052D70),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class _PremiumHistoryButton extends StatelessWidget {
  const _PremiumHistoryButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1B38),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22081A3C),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history_rounded, color: Colors.white, size: 17),
            const SizedBox(width: 6),
            Text(
              'View history',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _money(dynamic value) =>
    '₹${(num.tryParse('$value') ?? 0).toStringAsFixed(0)}';
Map<String, dynamic> _dataMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
double _amount(dynamic value) => num.tryParse('$value')?.toDouble() ?? 0;

class _NetPayBanner extends StatefulWidget {
  const _NetPayBanner({required this.mobile});
  final bool mobile;
  @override
  State<_NetPayBanner> createState() => _NetPayBannerState();
}

class _NetPayBannerState extends State<_NetPayBanner> {
  late final Future<Map<String, dynamic>> _data = HrmsPayslipApi.summary();

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _data,
    builder: (context, snapshot) {
      final payroll = _dataMap(snapshot.data?['payroll']);
      final paid = payroll['status'] == 'paid';
      final updatedSalary = _amount(
        payroll['net_pay'] ??
            payroll['updated_salary'] ??
            payroll['monthly_salary'],
      );
      if (widget.mobile) {
        return _PremiumSalaryHero(
          payroll: payroll,
          updatedSalary: updatedSalary,
          underReview: snapshot.data?['reviewRequired'] == true,
          paid: paid,
        );
      }
      return Container(
        constraints: BoxConstraints(minHeight: widget.mobile ? 216 : 285),
        padding: EdgeInsets.all(widget.mobile ? 20 : 34),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF101D38), Color(0xFF07132A)],
          ),
          border: Border.all(color: const Color(0xFF1D3157)),
          borderRadius: BorderRadius.circular(widget.mobile ? 20 : 14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26002061),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            if (widget.mobile)
              Positioned(
                right: -40,
                top: -52,
                child: Container(
                  width: 165,
                  height: 165,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0x332D75F6), Color(0x002D75F6)],
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Updated Salary',
                        style: widget.mobile
                            ? GoogleFonts.inter(
                                color: const Color(0xFFB9D5FF),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .7,
                              )
                            : const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                              ),
                      ),
                      SizedBox(height: widget.mobile ? 7 : 10),
                      if (payroll.isEmpty)
                        Text(
                          snapshot.data?['reviewRequired'] == true
                              ? 'Payroll under review'
                              : 'Payroll not generated',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: widget.mobile ? 22 : 28,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else ...[
                        Text(
                          _money(updatedSalary),
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: widget.mobile ? 38 : 50,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Earned to Date: ${_money(updatedSalary)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${payroll['pay_month']}/${payroll['pay_year']}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: widget.mobile ? 18 : 21,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 13),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF005A43),
                          border: Border.all(color: const Color(0xFF008F63)),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 5,
                              backgroundColor: paid
                                  ? const Color(0xFF1DDA83)
                                  : const Color(0xFFB7C6DF),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              paid ? 'PAID' : 'UPDATES DAILY',
                              style: TextStyle(
                                color: paid
                                    ? const Color(0xFF2DE38E)
                                    : const Color(0xFFD6E0EF),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: widget.mobile ? 8 : 24),
                _WalletArtwork(size: widget.mobile ? 96 : 190),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _PremiumSalaryHero extends StatelessWidget {
  const _PremiumSalaryHero({
    required this.payroll,
    required this.updatedSalary,
    required this.underReview,
    required this.paid,
  });

  final Map<String, dynamic> payroll;
  final double updatedSalary;
  final bool underReview;
  final bool paid;

  @override
  Widget build(BuildContext context) {
    final paidDays = _amount(payroll['paid_days']);
    final workingDays = _amount(payroll['working_days']);
    final fraction = workingDays > 0
        ? (paidDays / workingDays).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final period = payroll.isEmpty
        ? 'Current payroll'
        : '${payroll['pay_month']}/${payroll['pay_year']}';

    return Container(
      width: double.infinity,
      height: 230,
      padding: const EdgeInsets.fromLTRB(25, 28, 25, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF101D38), Color(0xFF0C182F)],
        ),
        border: Border.all(color: const Color(0xFF1C3156)),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24081732),
            blurRadius: 20,
            offset: Offset(0, 9),
          ),
        ],
      ),
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
                    Text(
                      'UPDATED SALARY',
                      style: GoogleFonts.inter(
                        color: const Color(0xFFB7D5FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .75,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      payroll.isEmpty
                          ? (underReview ? 'Under review' : 'Not generated')
                          : _money(updatedSalary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: payroll.isEmpty ? 23 : 39,
                        height: 1,
                        letterSpacing: -1.3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 11),
                    Text(
                      payroll.isEmpty
                          ? 'Payroll details will appear here.'
                          : 'Earned to Date: ${_money(updatedSalary)} • $period',
                      style: GoogleFonts.inter(
                        color: const Color(0xFFD7E6FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2869E3), Color(0xFF1A4ECD)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF4A83F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33030612),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(height: 1, color: const Color(0xFF294264)),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: paid
                      ? const Color(0xFF008866)
                      : const Color(0xFF1B3558),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 7,
                      color: paid
                          ? const Color(0xFF8BF4CE)
                          : const Color(0xFFB7D0F7),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      paid ? 'PAID' : 'UPDATES DAILY',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '${paidDays.toStringAsFixed(0)}  /  ${workingDays.toStringAsFixed(0)} Paid Days',
                style: GoogleFonts.robotoMono(
                  color: const Color(0xFFD3E5FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: fraction,
              backgroundColor: const Color(0xFF111F39),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF149BD7)),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletArtwork extends StatelessWidget {
  const _WalletArtwork({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0x1F61A8FF),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x33489EFF)),
          ),
        ),
        Icon(
          Icons.account_balance_wallet_rounded,
          color: const Color(0xFF9DBDE8),
          size: size * .56,
        ),
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
      ],
    ),
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
    child: Text(
      '₹',
      style: TextStyle(
        color: const Color(0xFF315C98),
        fontSize: size * .48,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _SalaryOverviewCard extends StatefulWidget {
  const _SalaryOverviewCard();
  @override
  State<_SalaryOverviewCard> createState() => _SalaryOverviewCardState();
}

String _monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

Future<void> _showPayrollHistory(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _PayrollHistoryDialog(),
  );
}

class _PayrollHistoryDialog extends StatefulWidget {
  const _PayrollHistoryDialog();
  @override
  State<_PayrollHistoryDialog> createState() => _PayrollHistoryDialogState();
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
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${names[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      insetPadding: mobile
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 42, vertical: 28),
      alignment: mobile ? Alignment.bottomCenter : null,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: const Radius.circular(24),
          bottom: mobile ? Radius.zero : const Radius.circular(20),
        ),
      ),
      child: SizedBox(
        width: mobile ? double.infinity : null,
        height: mobile ? MediaQuery.sizeOf(context).height * .92 : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: mobile ? double.infinity : 1750,
            maxHeight: mobile ? double.infinity : 820,
          ),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              final payload = snapshot.data ?? const <String, dynamic>{};
              final summary = _dataMap(payload['summary']);
              final rawItems = payload['items'];
              final items = rawItems is List
                  ? rawItems
                        .whereType<Map>()
                        .map((row) => Map<String, dynamic>.from(row))
                        .toList()
                  : <Map<String, dynamic>>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      mobile ? 20 : 30,
                      mobile ? 18 : 24,
                      mobile ? 12 : 18,
                      mobile ? 12 : 18,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Payroll history',
                            style: TextStyle(
                              fontSize: mobile ? 22 : 26,
                              fontWeight: FontWeight.w800,
                              color: employeeNavy,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: employeeLine),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _month,
                              icon: const Icon(
                                Icons.arrow_drop_down_rounded,
                                color: employeeMuted,
                              ),
                              items: _months
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(
                                        _displayMonth(m),
                                        style: const TextStyle(
                                          color: employeeNavy,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  _month = v;
                                  _future = HrmsPayslipApi.history(v);
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: employeeMuted,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1, color: employeeLine),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: mobile ? 20 : 30,
                      vertical: mobile ? 12 : 16,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final chipWidth = mobile
                            ? (constraints.maxWidth - 10) / 2
                            : 138.0;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _PayrollHeaderChip(
                              width: chipWidth,
                              label: 'Total salary',
                              value: _ledgerMoney(summary['monthly_salary']),
                            ),
                            _PayrollHeaderChip(
                              width: chipWidth,
                              label: 'Working days',
                              value:
                                  '${_amount(summary['working_days']).toStringAsFixed(0)}',
                            ),
                            _PayrollHeaderChip(
                              width: chipWidth,
                              label: 'Paid days',
                              value:
                                  '${_amount(summary['paid_days']).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}',
                            ),
                            _PayrollHeaderChip(
                              width: chipWidth,
                              label: 'LOP',
                              value:
                                  '${_amount(summary['lop_days']).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}',
                              valueColor: const Color(0xFFD93445),
                            ),
                            _PayrollHeaderChip(
                              width: chipWidth,
                              label: 'Net pay',
                              value: _ledgerMoney(summary['net_pay']),
                              valueColor: employeeBlue,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Container(height: 1, color: employeeLine),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        if (snapshot.connectionState == ConnectionState.waiting)
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        if (snapshot.hasError)
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(30),
                              child: Text(
                                'Unable to load payroll history.',
                                style: TextStyle(color: employeeMuted),
                              ),
                            ),
                          );
                        if (items.isEmpty)
                          return const Center(
                            child: Text(
                              'No payroll days are available for this period.',
                              style: TextStyle(color: employeeMuted),
                            ),
                          );
                        return mobile
                            ? _PayrollLedgerMobileList(items: items)
                            : _PayrollLedgerTable(items: items);
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      mobile ? 20 : 22,
                      8,
                      mobile ? 20 : 30,
                      mobile ? 12 : 18,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

String _ledgerMoney(dynamic value) {
  final amount = _amount(value);
  return amount == amount.roundToDouble()
      ? '₹${amount.toStringAsFixed(0)}'
      : '₹${amount.toStringAsFixed(2)}';
}

class _PayrollHeaderChip extends StatelessWidget {
  const _PayrollHeaderChip({
    required this.width,
    required this.label,
    required this.value,
    this.valueColor = employeeNavy,
  });
  final double width;
  final String label;
  final String value;
  final Color valueColor;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F7FD),
      border: Border.all(color: employeeLine),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: employeeMuted, fontSize: 11)),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ],
    ),
  );
}

class _PayrollLedgerMobileList extends StatelessWidget {
  const _PayrollLedgerMobileList({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
    itemCount: items.length,
    separatorBuilder: (_, __) => const SizedBox(height: 10),
    itemBuilder: (_, index) => _PayrollLedgerMobileCard(item: items[index]),
  );
}

class _PayrollLedgerMobileCard extends StatefulWidget {
  const _PayrollLedgerMobileCard({required this.item});

  final Map<String, dynamic> item;

  @override
  State<_PayrollLedgerMobileCard> createState() =>
      _PayrollLedgerMobileCardState();
}

class _PayrollLedgerMobileCardState extends State<_PayrollLedgerMobileCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final status = '${item['status'] ?? '—'}';
    final lateMinutes = _amount(item['late_minutes']);
    final details = <({String label, String value, Color color})>[
      (
        label: 'Salary',
        value: _ledgerMoney(item['salary']),
        color: employeeNavy,
      ),
      (
        label: 'Working',
        value: _amount(
          item['working'],
        ).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), ''),
        color: employeeNavy,
      ),
      (
        label: 'Check in',
        value: _payrollTime(item['check_in']),
        color: employeeNavy,
      ),
      (
        label: 'Check out',
        value: _payrollTime(item['check_out']),
        color: employeeNavy,
      ),
      (
        label: 'Late deduction time',
        value: _lateDuration(lateMinutes),
        color: employeeNavy,
      ),
      (
        label: 'Late deduction',
        value: _ledgerMoney(item['late_deduction']),
        color: const Color(0xFFE06E00),
      ),
      (
        label: 'Absent / LOP',
        value: _ledgerMoney(item['absent_deduction']),
        color: const Color(0xFFD93445),
      ),
      (
        label: 'Total deduction',
        value: _ledgerMoney(item['total_deduction']),
        color: const Color(0xFFD93445),
      ),
      (
        label: 'Present amount',
        value: _ledgerMoney(item['present_amount']),
        color: const Color(0xFF008944),
      ),
      (
        label: 'Updated salary',
        value: _ledgerMoney(item['updated_salary']),
        color: employeeBlue,
      ),
    ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: _expanded ? const Color(0xFFB8D1F9) : employeeLine,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: _expanded
                ? const [
                    BoxShadow(
                      color: Color(0x120B2D5C),
                      blurRadius: 12,
                      offset: Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _ledgerDate(item['date']),
                          style: const TextStyle(
                            color: employeeNavy,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _PayrollStatus(status: status),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Updated salary',
                        style: TextStyle(color: employeeMuted, fontSize: 11),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _ledgerMoney(item['updated_salary']),
                        style: const TextStyle(
                          color: employeeBlue,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: employeeMuted,
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 180),
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    children: [
                      const Divider(height: 1, color: employeeLine),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.45,
                        children: details
                            .map(
                              (detail) => _PayrollMobileDetail(
                                label: detail.label,
                                value: detail.value,
                                color: detail.color,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayrollMobileDetail extends StatelessWidget {
  const _PayrollMobileDetail({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F9FD),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: employeeMuted, fontSize: 10),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
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
          child: Column(
            children: [
              const _PayrollLedgerRow(header: true),
              ...items.map((item) => _PayrollLedgerRow(item: item)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PayrollLedgerRow extends StatelessWidget {
  const _PayrollLedgerRow({this.item, this.header = false});
  final Map<String, dynamic>? item;
  final bool header;
  static const _widths = [
    150.0,
    125.0,
    112.0,
    145.0,
    145.0,
    135.0,
    170.0,
    150.0,
    155.0,
    155.0,
    150.0,
    155.0,
  ];
  static const _labels = [
    'Date',
    'Salary',
    'Working',
    'Check in',
    'Check out',
    'Status',
    'Late deduction time',
    'Late deduction',
    'Absent / LOP',
    'Total deduction',
    'Present amount',
    'Updated salary',
  ];

  @override
  Widget build(BuildContext context) {
    if (header)
      return Container(
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7FD),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: List.generate(
            _labels.length,
            (i) => _PayrollLedgerCell(
              width: _widths[i],
              value: _labels[i],
              header: true,
            ),
          ),
        ),
      );
    final row = item!;
    final status = '${row['status'] ?? '—'}';
    final lateMinutes = _amount(row['late_minutes']);
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: employeeLine)),
      ),
      child: Row(
        children: [
          _PayrollLedgerCell(
            width: _widths[0],
            value: _ledgerDate(row['date']),
          ),
          _PayrollLedgerCell(
            width: _widths[1],
            value: _ledgerMoney(row['salary']),
          ),
          _PayrollLedgerCell(
            width: _widths[2],
            value: _amount(
              row['working'],
            ).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), ''),
          ),
          _PayrollLedgerCell(
            width: _widths[3],
            value: _payrollTime(row['check_in']),
          ),
          _PayrollLedgerCell(
            width: _widths[4],
            value: _payrollTime(row['check_out']),
          ),
          _PayrollLedgerCell(
            width: _widths[5],
            child: _PayrollStatus(status: status),
          ),
          _PayrollLedgerCell(
            width: _widths[6],
            value: _lateDuration(lateMinutes),
          ),
          _PayrollLedgerCell(
            width: _widths[7],
            value: _ledgerMoney(row['late_deduction']),
            color: const Color(0xFFE06E00),
          ),
          _PayrollLedgerCell(
            width: _widths[8],
            value: _ledgerMoney(row['absent_deduction']),
            color: const Color(0xFFD93445),
          ),
          _PayrollLedgerCell(
            width: _widths[9],
            value: _ledgerMoney(row['total_deduction']),
            color: const Color(0xFFD93445),
          ),
          _PayrollLedgerCell(
            width: _widths[10],
            value: _ledgerMoney(row['present_amount']),
            color: const Color(0xFF008944),
          ),
          _PayrollLedgerCell(
            width: _widths[11],
            value: _ledgerMoney(row['updated_salary']),
            color: const Color(0xFF1769E0),
          ),
        ],
      ),
    );
  }
}

class _PayrollLedgerCell extends StatelessWidget {
  const _PayrollLedgerCell({
    required this.width,
    this.value,
    this.child,
    this.header = false,
    this.color = employeeNavy,
  });
  final double width;
  final String? value;
  final Widget? child;
  final bool header;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child:
            child ??
            Text(
              value ?? '—',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: header ? employeeMuted : color,
                fontSize: header ? 13 : 14,
                fontWeight: header ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
      ),
    ),
  );
}

class _PayrollStatus extends StatelessWidget {
  const _PayrollStatus({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final value = status.toLowerCase();
    final present = value.contains('present') || value.contains('late');
    final absent = value.contains('absent') || value.contains('lop');
    final color = present
        ? const Color(0xFF008944)
        : absent
        ? const Color(0xFFD93445)
        : employeeMuted;
    final bg = present
        ? const Color(0xFFE1F8EA)
        : absent
        ? const Color(0xFFFFE8EA)
        : const Color(0xFFF0F3F8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _ledgerDate(dynamic value) {
  final raw = '$value';
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  const shortMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
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

/// Turns backend late minutes into a compact, employee-readable duration.
/// Examples: 0 -> —, 45 -> 45m, 130 -> 2h 10m.
String _lateDuration(num minutes) {
  final total = minutes.round();
  if (total <= 0) return '—';
  final hours = total ~/ 60;
  final remainder = total % 60;
  if (hours == 0) return remainder.toString() + 'm';
  if (remainder == 0) return hours.toString() + 'h';
  return hours.toString() + 'h ' + remainder.toString() + 'm';
}

class _SalaryOverviewCardState extends State<_SalaryOverviewCard> {
  late final Future<Map<String, dynamic>> _data = HrmsPayslipApi.summary();

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _data,
    builder: (context, snapshot) {
      final payroll = _dataMap(snapshot.data?['payroll']);
      final monthlySalary = _amount(payroll['monthly_salary']);
      final workingDays = _amount(payroll['working_days']);
      final paidDays = _amount(payroll['paid_days']);
      final lateDeduction = _amount(payroll['late_deductions']);
      final absenceDeduction = _amount(
        payroll['absent_deductions'] ?? payroll['deductions'],
      );
      final totalDeduction = lateDeduction + absenceDeduction;
      final deductionDays = _amount(payroll['lop_days']);
      final updatedSalary = _amount(
        payroll['net_pay'] ??
            payroll['updated_salary'] ??
            payroll['monthly_salary'],
      );
      final mobile = MediaQuery.sizeOf(context).width < 600;
      if (mobile) {
        return _MobileSalaryOverview(
          payroll: payroll,
          monthlySalary: monthlySalary,
          totalDeduction: totalDeduction,
          deductionDays: deductionDays,
          workingDays: workingDays,
          paidDays: paidDays,
          updatedSalary: updatedSalary,
        );
      }
      return SizedBox(
        width: double.infinity,
        child: EmployeeCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SalaryHeading('Salary Overview'),
              const SizedBox(height: 16),
              if (payroll.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    snapshot.data?['reviewRequired'] == true
                        ? 'Admin needs to correct an existing payroll record before salary payment details can be shown.'
                        : 'Payroll has not been generated for this employee.',
                    style: const TextStyle(color: employeeMuted),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: _OverviewMetric(
                        label: 'Salary / Month',
                        value: _money(monthlySalary),
                      ),
                    ),
                    const _OverviewDivider(),
                    Expanded(
                      child: _OverviewMetric(
                        label: 'Deduction',
                        value: totalDeduction > 0
                            ? '−${_money(totalDeduction)} / ${deductionDays.toStringAsFixed(0)} ${deductionDays == 1 ? 'day' : 'days'}'
                            : '₹0',
                      ),
                    ),
                    const _OverviewDivider(),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        color: const Color(0xFFF0F6FF),
                        child: _OverviewMetric(
                          label: 'Updated Salary',
                          value: _money(updatedSalary),
                          valueColor: employeeBlue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1, color: employeeLine),
                LabeledValue(
                  'Total Working Days',
                  workingDays.toStringAsFixed(0),
                ),
                const Divider(height: 1, color: employeeLine),
                LabeledValue(
                  'Earned to Date',
                  '${_money(updatedSalary)} / ${paidDays.toStringAsFixed(0)} ${paidDays == 1 ? 'day' : 'days'}',
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _MobileSalaryOverview extends StatelessWidget {
  const _MobileSalaryOverview({
    required this.payroll,
    required this.monthlySalary,
    required this.totalDeduction,
    required this.deductionDays,
    required this.workingDays,
    required this.paidDays,
    required this.updatedSalary,
  });

  final Map<String, dynamic> payroll;
  final double monthlySalary;
  final double totalDeduction;
  final double deductionDays;
  final double workingDays;
  final double paidDays;
  final double updatedSalary;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: employeeLine),
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0C18365D),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Salary Overview',
              style: GoogleFonts.inter(
                color: employeeNavy,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -.3,
              ),
            ),
            const Spacer(),
            Container(
              child: Text(
                payroll.isEmpty
                    ? 'Current month'
                    : '${payroll['pay_month']}  ${payroll['pay_year']}',
                style: GoogleFonts.robotoMono(
                  color: const Color(0xFF254367),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (payroll.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Payroll has not been generated for this employee.',
              style: GoogleFonts.inter(color: employeeMuted, fontSize: 12),
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: _MobileOverviewMetric(
                  label: 'Salary / Month',
                  value: _money(monthlySalary),
                  color: employeeNavy,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MobileOverviewMetric(
                  label: 'Deduction',
                  value: totalDeduction > 0
                      ? '−${_money(totalDeduction)}'
                      : '₹0',
                  helper: deductionDays > 0
                      ? '${deductionDays.toStringAsFixed(0)} days LOP'
                      : 'No deduction',
                  color: const Color(0xFFE33A4A),
                  tint: const Color(0xFFFFF3F4),
                  border: const Color(0xFFFFD8DD),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MobileOverviewMetric(
                  label: 'Updated',
                  value: _money(updatedSalary),
                  color: employeeBlue,
                  tint: const Color(0xFFEFF5FF),
                  border: const Color(0xFFC6DBFF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(height: 1, color: employeeLine),
          const SizedBox(height: 17),
          _MobileSummaryRow(
            label: 'Total Working Days',
            value: workingDays.toStringAsFixed(0),
          ),
          const SizedBox(height: 15),
          _MobileSummaryRow(
            label: 'Earned to Date',
            value:
                '${_money(updatedSalary)}  ·  ${paidDays.toStringAsFixed(0)} paid days',
          ),
          const SizedBox(height: 17),
          Container(height: 1, color: employeeLine),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showPayrollHistory(context),
              icon: const Icon(Icons.history_rounded, size: 20),
              label: Text(
                'View deduction history',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: employeeBlue,
                backgroundColor: const Color(0xFFF0F6FF),
                side: const BorderSide(color: Color(0xFFB9D4FF)),
                minimumSize: const Size.fromHeight(53),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(27),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _MobileOverviewMetric extends StatelessWidget {
  const _MobileOverviewMetric({
    required this.label,
    required this.value,
    required this.color,
    this.helper,
    this.tint = const Color(0xFFF7F9FD),
    this.border = employeeLine,
  });
  final String label;
  final String value;
  final String? helper;
  final Color color;
  final Color tint;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
    height: 91,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: tint,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: employeeMuted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: -.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          helper ?? 'Current payroll',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(color: employeeMuted, fontSize: 8),
        ),
      ],
    ),
  );
}

class _MobileSummaryRow extends StatelessWidget {
  const _MobileSummaryRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(label, style: GoogleFonts.inter(color: employeeMuted, fontSize: 12)),
      const Spacer(),
      Text(
        value,
        style: GoogleFonts.inter(
          color: employeeNavy,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.label,
    required this.value,
    this.valueColor = employeeNavy,
  });
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: employeeMuted, fontSize: 11)),
      const SizedBox(height: 7),
      Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: valueColor,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _OverviewDivider extends StatelessWidget {
  const _OverviewDivider();
  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 62,
    child: VerticalDivider(width: 24, color: employeeLine),
  );
}

class _SalaryBreakdownCard extends StatefulWidget {
  const _SalaryBreakdownCard();
  @override
  State<_SalaryBreakdownCard> createState() => _SalaryBreakdownCardState();
}

class _SalaryBreakdownCardState extends State<_SalaryBreakdownCard> {
  late final Future<Map<String, dynamic>> _data = HrmsPayslipApi.summary();

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _data,
    builder: (context, snapshot) {
      final compensation = _dataMap(snapshot.data?['compensation']);
      final payroll = _dataMap(snapshot.data?['payroll']);
      return SizedBox(
        width: double.infinity,
        child: EmployeeCard(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SalaryHeading('Salary Breakdown'),
              const SizedBox(height: 10),
              if (compensation.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Salary not configured. Contact Admin to set your compensation.',
                    style: TextStyle(color: employeeMuted),
                  ),
                )
              else if (payroll.isEmpty) ...[
                LabeledValue(
                  'Monthly Salary',
                  _money(compensation['monthly_salary']),
                ),
                const Divider(height: 1, color: employeeLine),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    snapshot.data?['reviewRequired'] == true
                        ? 'Payroll correction required.'
                        : 'Payroll not generated yet.',
                    style: const TextStyle(color: employeeMuted),
                  ),
                ),
              ] else ...[
                LabeledValue(
                  'Monthly Salary',
                  _money(payroll['monthly_salary']),
                ),
                const Divider(height: 1, color: employeeLine),
                LabeledValue(
                  'Late Deduction',
                  '−${_money(payroll['late_deductions'] ?? 0)}',
                ),
                const Divider(height: 1, color: employeeLine),
                LabeledValue(
                  'Absent / Leave Deduction',
                  '−${_money(payroll['absent_deductions'] ?? payroll['deductions'])}',
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _SalaryHeading extends StatelessWidget {
  const _SalaryHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: employeeNavy,
      fontSize: 20,
      fontWeight: FontWeight.w800,
    ),
  );
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
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _items,
    builder: (context, snapshot) {
      if (MediaQuery.sizeOf(context).width < 600) {
        final items = snapshot.data ?? const <Map<String, dynamic>>[];
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: employeeLine),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0C18365D),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Recent Payslips',
                    style: GoogleFonts.inter(
                      color: employeeNavy,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.3,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9F2FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${items.length} Available',
                      style: GoogleFonts.inter(
                        color: employeeBlue,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              if (snapshot.connectionState != ConnectionState.done)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (snapshot.hasError)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Unable to load payslips',
                    style: GoogleFonts.inter(
                      color: employeeMuted,
                      fontSize: 12,
                    ),
                  ),
                )
              else if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No paid payslips are available yet.',
                    style: GoogleFonts.inter(
                      color: employeeMuted,
                      fontSize: 12,
                    ),
                  ),
                )
              else ...[
                ...items
                    .take(3)
                    .map(
                      (item) =>
                          _PremiumPayslipRow(item: item, onChanged: _refresh),
                    ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Payslips are available for download after payroll processing.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: employeeMuted,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }
      return SizedBox(
        width: double.infinity,
        child: EmployeeCard(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SalaryHeading('Recent Payslips'),
              SizedBox(height: 10),
              if (snapshot.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Unable to load payslips',
                    style: TextStyle(color: employeeMuted),
                  ),
                )
              else if ((snapshot.data ?? const <Map<String, dynamic>>[])
                  .isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No paid payslips are available yet.',
                    style: TextStyle(color: employeeMuted),
                  ),
                )
              else
                ...((snapshot.data ?? const <Map<String, dynamic>>[])
                    .take(3)
                    .map(
                      (item) =>
                          _LivePayslipRow(item: item, onChanged: _refresh),
                    )),
            ],
          ),
        ),
      );
    },
  );
}

class _PremiumPayslipRow extends StatelessWidget {
  const _PremiumPayslipRow({required this.item, required this.onChanged});
  final Map<String, dynamic> item;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final status = '${item['request_status']}';
    final approved = status == 'approved';
    final approvedGreen = const Color(0xFF079669);
    final iconTint = approved
        ? const Color(0xFFEAFBF3)
        : const Color(0xFFEAF3FF);
    final iconBorder = approved
        ? const Color(0xFF9AE6C6)
        : const Color(0xFFBED8FF);
    final accent = approved ? approvedGreen : employeeBlue;
    final label = approved
        ? 'Approved for download'
        : status == 'pending'
        ? 'Approval pending'
        : status == 'rejected'
        ? 'Request rejected'
        : 'Request download approval';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFE),
          border: Border.all(color: employeeLine),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconTint,
                border: Border.all(color: iconBorder),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(Icons.receipt_long_outlined, color: accent, size: 23),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['pay_month']}/${item['pay_year']}',
                    style: GoogleFonts.inter(
                      color: employeeNavy,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: approved ? approvedGreen : employeeMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _ledgerMoney(item['net_pay']),
                  style: GoogleFonts.robotoMono(
                    color: approved ? const Color(0xFF067653) : employeeNavy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _showPayslipAction(context, item, onChanged),
                    child: Ink(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: approved
                            ? approvedGreen
                            : const Color(0xFFEAF3FF),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        approved
                            ? Icons.download_rounded
                            : Icons.arrow_forward_rounded,
                        color: approved ? Colors.white : employeeBlue,
                        size: 21,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPayslipAction(
    BuildContext context,
    Map<String, dynamic> record,
    VoidCallback refresh,
  ) async {
    final status = '${record['request_status']}';
    try {
      if (status == 'approved') {
        await HrmsPayslipApi.download(int.parse('${record['id']}'));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            employeePremiumSnackBar(
              'Payslip download started.',
              isSuccess: true,
            ),
          );
        }
      } else if (status == 'not_requested') {
        await HrmsPayslipApi.request(int.parse('${record['id']}'));
        refresh();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            employeePremiumSnackBar(
              'Payslip request sent for approval.',
              isSuccess: true,
            ),
          );
        }
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          employeePremiumSnackBar(
            status == 'rejected'
                ? 'This payslip request was rejected.'
                : 'Payslip request is awaiting approval.',
            isError: status == 'rejected',
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          employeePremiumSnackBar(
            error.toString().replaceFirst('Exception: ', ''),
            isError: true,
          ),
        );
      }
    }
  }
}

class _LivePayslipRow extends StatefulWidget {
  const _LivePayslipRow({required this.item, required this.onChanged});
  final Map<String, dynamic> item;
  final VoidCallback onChanged;
  @override
  State<_LivePayslipRow> createState() => _LivePayslipRowState();
}

class _LivePayslipRowState extends State<_LivePayslipRow> {
  bool busy = false;
  String get status => '${widget.item['request_status']}';
  String get month => '${widget.item['pay_month']}/${widget.item['pay_year']}';
  Future<void> download(BuildContext context) async {
    if (status == 'not_requested') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Send payslip request?'),
          content: const Text(
            'Send this download request to Admin for approval?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Send request'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted || !context.mounted) return;
    }
    setState(() => busy = true);
    try {
      if (status == 'approved') {
        await HrmsPayslipApi.download(int.parse('${widget.item['id']}'));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payslip download started.')),
        );
      } else if (status == 'not_requested') {
        await HrmsPayslipApi.request(int.parse('${widget.item['id']}'));
        widget.onChanged();
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'rejected'
                  ? 'Your request was rejected.'
                  : 'Your request is awaiting Admin approval.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                month,
                style: const TextStyle(
                  color: employeeNavy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                status == 'approved'
                    ? 'Approved for download'
                    : status == 'pending'
                    ? 'Approval pending'
                    : status == 'rejected'
                    ? 'Request rejected'
                    : 'Request download approval',
                style: const TextStyle(color: employeeMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        Text(
          '₹${widget.item['net_pay']}',
          style: const TextStyle(
            color: employeeNavy,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 7),
        IconButton(
          tooltip: status == 'approved'
              ? 'Download payslip'
              : 'Request payslip',
          onPressed: busy ? null : () => download(context),
          icon: Icon(
            Icons.download_rounded,
            color: status == 'approved'
                ? const Color(0xFF158C20)
                : employeeBlue,
          ),
        ),
      ],
    ),
  );
}
