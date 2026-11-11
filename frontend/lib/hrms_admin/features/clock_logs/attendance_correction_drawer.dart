import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/hrms_clock_logs_api.dart';

const _blue = Color(0xFF0B2C7B);
const _line = Color(0xFFDCE5F4);

Future<void> showAttendanceCorrectionDrawer(
  BuildContext context, {
  required int employeeId,
  required String employeeName,
  required String staffId,
  required DateTime initialMonth,
  required VoidCallback onChanged,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close attendance correction',
  barrierColor: const Color(0xA6000000),
  transitionDuration: const Duration(milliseconds: 260),
  pageBuilder: (context, _, __) => Align(
    alignment: Alignment.centerRight,
    child: _AttendanceCorrectionDrawer(
      employeeId: employeeId,
      employeeName: employeeName,
      staffId: staffId,
      initialMonth: initialMonth,
      onChanged: onChanged,
    ),
  ),
  transitionBuilder: (_, animation, __, child) => SlideTransition(
    position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    ),
    child: child,
  ),
);

class _AttendanceCorrectionDrawer extends StatefulWidget {
  const _AttendanceCorrectionDrawer({
    required this.employeeId,
    required this.employeeName,
    required this.staffId,
    required this.initialMonth,
    required this.onChanged,
  });
  final int employeeId;
  final String employeeName;
  final String staffId;
  final DateTime initialMonth;
  final VoidCallback onChanged;

  @override
  State<_AttendanceCorrectionDrawer> createState() => _AttendanceCorrectionDrawerState();
}

class _AttendanceCorrectionDrawerState extends State<_AttendanceCorrectionDrawer> {
  late DateTime _month;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _days = const [];
  Map<String, dynamic>? _selected;
  String _chosenStatus = 'present';
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialMonth.year, widget.initialMonth.month);
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _selected = null;
    });
    try {
      final data = await HrmsClockLogsApi.calendar(employeeId: widget.employeeId, month: _month);
      if (!mounted) return;
      setState(() {
        _days = (data['days'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _select(Map<String, dynamic> day) {
    final status = '${day['status']}'.toLowerCase();
    setState(() {
      _selected = day;
      _chosenStatus = status == 'present' ? 'absent' : 'present';
      _reason.clear();
    });
  }

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null || _saving) return;
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Enter an admin reason before saving.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await HrmsClockLogsApi.correctStatus(
        employeeId: widget.employeeId,
        date: DateTime.parse('${selected['date']}'),
        status: _chosenStatus,
        reason: reason,
      );
      if (!mounted) return;
      widget.onChanged();
      final warning = result['data'] is Map ? result['data']['warning']?.toString() : null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(warning ?? result['message']?.toString() ?? 'Attendance status corrected.'),
      ));
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 530,
        child: Column(children: [
          _header(),
          const Divider(height: 1, color: Color(0xFFE7EAF0)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
              child: Column(children: [
                _monthControl(),
                const SizedBox(height: 10),
                _calendar(),
                const SizedBox(height: 16),
                _correctionPanel(),
              ]),
            ),
          ),
        ]),
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 10, 12),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${widget.employeeName} — ${DateFormat('MMMM yyyy').format(_month)}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF303B50), fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Employee ID: ${widget.staffId}', style: const TextStyle(color: Color(0xFF6374A5), fontSize: 12)),
      ])),
      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Color(0xFF657080))),
    ]),
  );

  Widget _monthControl() => Row(children: [
    IconButton(onPressed: _saving ? null : () { setState(() => _month = DateTime(_month.year, _month.month - 1)); _load(); }, icon: const Icon(Icons.chevron_left, color: Color(0xFF647084))),
    Expanded(child: Text(DateFormat('MMMM yyyy').format(_month), textAlign: TextAlign.center,
        style: const TextStyle(color: _blue, fontSize: 18, fontWeight: FontWeight.w700))),
    IconButton(onPressed: _saving ? null : () { setState(() => _month = DateTime(_month.year, _month.month + 1)); _load(); }, icon: const Icon(Icons.chevron_right, color: Color(0xFF647084))),
  ]);

  Widget _calendar() {
    if (_loading) return const SizedBox(height: 360, child: Center(child: CircularProgressIndicator()));
    if (_error != null && _days.isEmpty) return SizedBox(height: 250, child: Center(child: TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(_error!))));
    final first = DateTime(_month.year, _month.month).weekday % 7;
    final cells = <Widget>[...List.generate(first, (_) => const SizedBox())];
    cells.addAll(_days.map(_dayCell));
    return Column(children: [
      const Row(children: [
        _Weekday('Sun'), _Weekday('Mon'), _Weekday('Tue'), _Weekday('Wed'), _Weekday('Thu'), _Weekday('Fri'), _Weekday('Sat'),
      ]),
      const SizedBox(height: 6),
      GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: .83, children: cells),
    ]);
  }

  Widget _dayCell(Map<String, dynamic> day) {
    final selected = _selected?['date'] == day['date'];
    final status = '${day['status']}';
    final style = _badge(status);
    return InkWell(
      onTap: _saving ? null : () => _select(day),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: selected ? const Color(0xFF1769E0) : _line, width: selected ? 1.6 : 1),
        ),
        child: Column(children: [
          Text('${day['day']}', style: TextStyle(color: selected ? const Color(0xFF1769E0) : _blue, fontWeight: FontWeight.w600)),
          const SizedBox(height: 7),
          if (status != 'No record') Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            decoration: BoxDecoration(color: style.$1, borderRadius: BorderRadius.circular(3)),
            child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: TextStyle(color: style.$2, fontSize: 8, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  (Color, Color) _badge(String status) {
    final value = status.toLowerCase();
    if (value == 'present') return (const Color(0xFFDDF6EA), const Color(0xFF078A48));
    if (value == 'absent' || value == 'no record') return (const Color(0xFFFFE6E8), const Color(0xFFD93445));
    if (value == 'late' || value == 'early exit') return (const Color(0xFFFFEDD9), const Color(0xFFE16E00));
    if (value == 'leave' || value == 'holiday') return (const Color(0xFFF0E5FF), const Color(0xFF7B3FBE));
    return (const Color(0xFFEDF0F5), const Color(0xFF657080));
  }

  Widget _correctionPanel() {
    final day = _selected;
    if (day == null) return _message('Select a date to see its attendance and make a correction.');
    if (day['editable'] != true) return _message('This date cannot be corrected here\n(future date, leave, holiday, weekly off, or outside employment date).');
    final status = '${day['status']}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Correct attendance — ${day['date']}', style: const TextStyle(color: _blue, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _detail('Current', status), _detail('Check in', '${day['checkIn'] ?? '—'}'), _detail('Check out', '${day['checkOut'] ?? '—'}'),
        if (day['adminReason'] != null) _detail('Previous Admin reason', '${day['adminReason']}'),
        const SizedBox(height: 13),
        Row(children: [
          _statusChoice('present', 'Present', const Color(0xFF078A48)),
          const SizedBox(width: 9),
          _statusChoice('absent', 'Absent', const Color(0xFFD93445)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _reason,
          enabled: !_saving,
          maxLength: 1000,
          minLines: 3,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Admin reason', hintText: 'Explain why this status is being corrected',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 9), child: Text(_error!, style: const TextStyle(color: Color(0xFFC62828), fontSize: 12))),
        SizedBox(width: double.infinity, height: 43, child: FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1769E0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Save Correction'),
        )),
      ]),
    );
  }

  Widget _message(String text) => Container(
    width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
    decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(12)),
    child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF4E5A70), fontSize: 15, height: 1.45)),
  );

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: RichText(text: TextSpan(style: const TextStyle(color: Color(0xFF4E5A70), fontSize: 13), children: [
      TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: value),
    ])),
  );

  Widget _statusChoice(String value, String label, Color color) => ChoiceChip(
    label: Text(label), selected: _chosenStatus == value, onSelected: _saving ? null : (_) => setState(() => _chosenStatus = value),
    selectedColor: color.withValues(alpha: .13), side: BorderSide(color: _chosenStatus == value ? color : _line),
    labelStyle: TextStyle(color: _chosenStatus == value ? color : const Color(0xFF4E5A70), fontWeight: FontWeight.w600),
  );
}

class _Weekday extends StatelessWidget {
  const _Weekday(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF556A99), fontSize: 11)));
}
