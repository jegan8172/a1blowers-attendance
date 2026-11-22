import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/api_config.dart';
import '../../services/auth_service.dart';
import '../shared/employee_ui.dart';

class _CompactPermissionCalendar extends StatefulWidget {
  const _CompactPermissionCalendar({required this.initialDate});
  final DateTime initialDate;

  @override
  State<_CompactPermissionCalendar> createState() => _CompactPermissionCalendarState();
}

class _CompactPermissionCalendarState extends State<_CompactPermissionCalendar> {
  late DateTime _shownMonth;

  @override
  void initState() {
    super.initState();
    _shownMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
  }

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(_shownMonth.year, _shownMonth.month).weekday % 7;
    final dayCount = DateUtils.getDaysInMonth(_shownMonth.year, _shownMonth.month);
    final totalCells = ((firstWeekday + dayCount + 6) ~/ 7) * 7;
    const weekDays = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
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
              IconButton(onPressed: () => setState(() => _shownMonth = DateTime(_shownMonth.year, _shownMonth.month - 1)), icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 21), color: const Color(0xFF334155), splashRadius: 18),
              IconButton(onPressed: () => setState(() => _shownMonth = DateTime(_shownMonth.year, _shownMonth.month + 1)), icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 21), color: const Color(0xFF334155), splashRadius: 18),
            ]),
            const SizedBox(height: 3),
            Row(children: weekDays.map((day) => Expanded(child: Center(child: Text(day, style: GoogleFonts.inter(color: employeeNavy, fontSize: 10, fontWeight: FontWeight.w700))))).toList()),
            const SizedBox(height: 5),
            GridView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: totalCells,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisExtent: 28),
              itemBuilder: (_, index) {
                final day = index - firstWeekday + 1;
                if (day < 1 || day > dayCount) return const SizedBox.shrink();
                final selected = widget.initialDate.year == _shownMonth.year && widget.initialDate.month == _shownMonth.month && widget.initialDate.day == day;
                return InkWell(borderRadius: BorderRadius.circular(5), onTap: () => Navigator.pop(context, DateTime(_shownMonth.year, _shownMonth.month, day)), child: Center(child: Container(width: 25, height: 25, alignment: Alignment.center, decoration: BoxDecoration(color: selected ? employeeBlue : Colors.transparent, borderRadius: BorderRadius.circular(4)), child: Text('$day', style: GoogleFonts.robotoMono(color: selected ? Colors.white : employeeNavy, fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))))) ;
              },
            ),
            const Divider(height: 17, color: Color(0xFFE2E8F0)),
            Row(children: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Clear', style: GoogleFonts.inter(color: employeeBlue, fontSize: 11, fontWeight: FontWeight.w700))), const Spacer(), TextButton(onPressed: () => Navigator.pop(context, DateTime.now()), child: Text('Today', style: GoogleFonts.inter(color: employeeBlue, fontSize: 11, fontWeight: FontWeight.w700)))])
          ]),
        ),
      ),
    );
  }
}

class _CompactPermissionTimePicker extends StatefulWidget {
  const _CompactPermissionTimePicker({required this.initialTime, required this.title});
  final TimeOfDay initialTime;
  final String title;

  @override
  State<_CompactPermissionTimePicker> createState() => _CompactPermissionTimePickerState();
}

class _CompactPermissionTimePickerState extends State<_CompactPermissionTimePicker> {
  late int _hour;
  late int _minute;
  late bool _isPm;

  @override
  void initState() {
    super.initState();
    _isPm = widget.initialTime.hour >= 12;
    _hour = widget.initialTime.hourOfPeriod == 0 ? 12 : widget.initialTime.hourOfPeriod;
    _minute = widget.initialTime.minute;
  }

  TimeOfDay get _result => TimeOfDay(hour: (_hour % 12) + (_isPm ? 12 : 0), minute: _minute);

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 54),
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: SizedBox(
      width: 310,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: GoogleFonts.inter(color: employeeNavy, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text('Choose a time, then apply.', style: GoogleFonts.inter(color: employeeMuted, fontSize: 11)),
          const SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _timeStepper(label: 'HOUR', value: _hour.toString().padLeft(2, '0'), increase: () => setState(() => _hour = _hour == 12 ? 1 : _hour + 1), decrease: () => setState(() => _hour = _hour == 1 ? 12 : _hour - 1))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 28), child: Text(':', style: TextStyle(color: Color(0xFF0F172A), fontSize: 27, fontWeight: FontWeight.w700))),
            Expanded(child: _timeStepper(label: 'MIN', value: _minute.toString().padLeft(2, '0'), increase: () => setState(() => _minute = (_minute + 1) % 60), decrease: () => setState(() => _minute = (_minute + 59) % 60))),
          ]),
          const SizedBox(height: 14),
          Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)), child: Row(children: [Expanded(child: _ampmButton('AM', !_isPm, () => setState(() => _isPm = false))), Expanded(child: _ampmButton('PM', _isPm, () => setState(() => _isPm = true)))])),
          const SizedBox(height: 14),
          Row(children: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF6845B0), fontWeight: FontWeight.w700))),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context, _result), child: Text('Apply', style: GoogleFonts.inter(color: const Color(0xFF0F52BA), fontWeight: FontWeight.w800))),
          ]),
        ]),
      ),
    ),
  );

  Widget _timeStepper({required String label, required String value, required VoidCallback increase, required VoidCallback decrease}) => Container(
    height: 86,
    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(14)),
    child: Column(children: [IconButton(onPressed: increase, padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(height: 24, width: 42), splashRadius: 16, icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 19, color: Color(0xFF64748B))), Expanded(child: Center(child: Text(value, style: GoogleFonts.robotoMono(color: employeeNavy, fontSize: 27, fontWeight: FontWeight.w700))),), IconButton(onPressed: decrease, padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(height: 24, width: 42), splashRadius: 16, icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 19, color: Color(0xFF64748B)))]),
  );

  Widget _ampmButton(String label, bool selected, VoidCallback onTap) => TextButton(onPressed: onTap, style: TextButton.styleFrom(minimumSize: const Size(0, 36), padding: EdgeInsets.zero, foregroundColor: selected ? Colors.white : employeeMuted, backgroundColor: selected ? const Color(0xFF0F52BA) : Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))), child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800)));
}

class _PremiumPermissionTypeMenu extends StatelessWidget {
  const _PremiumPermissionTypeMenu({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  static const _options = <String, String>{
    'permission': 'Permission',
    'attendance_regularization': 'Attendance regularization (app crash)',
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => MenuAnchor(
      alignmentOffset: const Offset(0, 2),
      style: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
        maximumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 150)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        elevation: const WidgetStatePropertyAll(7),
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.white),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(2), side: const BorderSide(color: Color(0xFF94A3B8)))),
      ),
      menuChildren: _options.entries.map((entry) {
        final selected = entry.key == value;
        return MenuItemButton(
          onPressed: () => onChanged(entry.key),
          style: ButtonStyle(padding: const WidgetStatePropertyAll(EdgeInsets.zero), minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0))),
          child: Container(width: constraints.maxWidth, height: 38, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 40), color: selected ? employeeBlue : Colors.white, child: Text(entry.value, style: GoogleFonts.inter(color: selected ? Colors.white : employeeNavy, fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
        );
      }).toList(),
      builder: (context, controller, child) => InkWell(
        onTap: controller.isOpen ? controller.close : controller.open,
        borderRadius: BorderRadius.circular(12),
        child: Container(height: 48, padding: const EdgeInsets.symmetric(horizontal: 13), decoration: BoxDecoration(color: const Color(0xFFF8FAFC), border: Border.all(color: employeeBlue, width: 1.3), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.assignment_outlined, color: Color(0xFF0F52BA), size: 19), const SizedBox(width: 12), Expanded(child: Text(_options[value] ?? 'Permission', style: GoogleFonts.inter(color: employeeNavy, fontSize: 13, fontWeight: FontWeight.w600))), const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF475569), size: 20)])),
      ),
    ),
  );
}

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
  String _requestType = 'permission';

  bool _loading = false;
  bool _submitting = false;
  List<dynamic> _history = [];

  Widget _buildMobileRequest(BuildContext context) {
    final isPermission = _requestType == 'permission';
    final durationMinutes = (_endTime.hour * 60 + _endTime.minute) - (_startTime.hour * 60 + _startTime.minute);
    final durationLabel = durationMinutes > 0 ? '${durationMinutes ~/ 60}h ${(durationMinutes % 60).toString().padLeft(2, '0')}m Window' : 'Set time window';
    final outline = OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12));
    final focusOutline = outline.copyWith(borderSide: const BorderSide(color: Color(0xFF0F52BA), width: 1.6));
    InputDecoration fieldDecoration({required String hint, required IconData icon}) => InputDecoration(
      hintText: hint, hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
      prefixIcon: Icon(icon, color: const Color(0xFF0F52BA), size: 19),
      filled: true, fillColor: const Color(0xFFF8FAFC), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: outline, enabledBorder: outline, focusedBorder: focusOutline,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const MobileEmployeeHeader(showGreeting: false),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Permission', style: GoogleFonts.inter(color: employeeNavy, fontSize: 25, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Row(children: [Text('Hello, Okash', style: GoogleFonts.inter(color: employeeMuted, fontSize: 11)), const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('•', style: TextStyle(color: Color(0xFF94A3B8)))), Text('EMP1008', style: GoogleFonts.robotoMono(color: employeeBlue, fontSize: 11, fontWeight: FontWeight.w700))])])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: const Color(0xFFE0EDFF), border: Border.all(color: const Color(0xFFBFDBFE)), borderRadius: BorderRadius.circular(99)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.verified_user_outlined, size: 14, color: Color(0xFF0F52BA)), const SizedBox(width: 5), Text('2 Passes Left', style: GoogleFonts.inter(color: const Color(0xFF072B66), fontSize: 10, fontWeight: FontWeight.w800))])),
      ]),
      const SizedBox(height: 16),
      Container(width: double.infinity, padding: const EdgeInsets.all(18), decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0F172A), Color(0xFF1E293B)]), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF263B5F)), boxShadow: const [BoxShadow(color: Color(0x260F172A), blurRadius: 16, offset: Offset(0, 7))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(width: 48, height: 48, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0F52BA), Color(0xFF1D4ED8)]), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x663B82F6))), child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 26)), const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Permission Request', style: GoogleFonts.inter(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text('Select your time away and send it for approval.', style: GoogleFonts.inter(color: const Color(0xFFBFDBFE), fontSize: 11))]))]),
        const SizedBox(height: 15), const Divider(height: 1, color: Color(0x334E8BEB)), const SizedBox(height: 11),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: const Color(0x330F52BA), border: Border.all(color: const Color(0x553B82F6)), borderRadius: BorderRadius.circular(99)), child: Text('MANAGER APPROVAL', style: GoogleFonts.inter(color: const Color(0xFFDBEAFE), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: .35))), Row(children: [const Icon(Icons.bolt_rounded, color: Color(0xFF93C5FD), size: 15), const SizedBox(width: 4), Text('PASS-${DateFormat('MMM-dd').format(_selectedDate).toUpperCase()}', style: GoogleFonts.robotoMono(color: const Color(0xFFBFDBFE), fontSize: 10, fontWeight: FontWeight.w700))])]),
      ])),
      const SizedBox(height: 16),
      Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(18, 18, 18, 20), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x120F172A), blurRadius: 14, offset: Offset(0, 5))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(height: 3, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFBFDBFE), Color(0xFF0F52BA), Color(0xFFBFDBFE)]), borderRadius: BorderRadius.circular(99))),
        const SizedBox(height: 16),
        Text('Request Type', style: GoogleFonts.inter(color: employeeNavy, fontSize: 13, fontWeight: FontWeight.w800)), const SizedBox(height: 7),
        _PremiumPermissionTypeMenu(value: _requestType, onChanged: (value) => setState(() => _requestType = value)),
        const SizedBox(height: 13),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFEFF6FF), border: Border.all(color: const Color(0xFFBFDBFE)), borderRadius: BorderRadius.circular(12)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(isPermission ? Icons.schedule_send_rounded : Icons.rule_folder_outlined, color: const Color(0xFF0F52BA), size: 19), const SizedBox(width: 9), Expanded(child: Text(isPermission ? 'Short-duration permission up to 2 hours per pass. Counts toward monthly allowance.' : 'Use regularization only for a missed attendance event caused by an app issue.', style: GoogleFonts.inter(color: const Color(0xFF072B66), fontSize: 11, height: 1.35, fontWeight: FontWeight.w600)))])),
        const SizedBox(height: 16),
        Text(isPermission ? 'Permission Date' : 'Attendance Date', style: GoogleFonts.inter(color: employeeNavy, fontSize: 13, fontWeight: FontWeight.w800)), const SizedBox(height: 7),
        TextField(controller: _dateCtrl, readOnly: true, onTap: _pickDate, style: GoogleFonts.robotoMono(color: employeeNavy, fontSize: 12, fontWeight: FontWeight.w600), decoration: fieldDecoration(hint: 'Select date', icon: Icons.calendar_today_outlined)),
        if (isPermission) ...[
          const SizedBox(height: 16),
          Row(children: [
            Text('Time Away', style: GoogleFonts.inter(color: employeeNavy, fontSize: 13, fontWeight: FontWeight.w800)),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFE0EDFF), border: Border.all(color: const Color(0xFFBFDBFE)), borderRadius: BorderRadius.circular(99)), child: Text(durationLabel, style: GoogleFonts.robotoMono(color: const Color(0xFF072B66), fontSize: 10, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 8),
          InkWell(onTap: _pickTimeRange, borderRadius: BorderRadius.circular(12), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13), decoration: BoxDecoration(color: const Color(0xFFF8FAFC), border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.schedule_rounded, color: Color(0xFF0F52BA), size: 18), const SizedBox(width: 8), Expanded(child: Text(_formatTimeOfDay(_startTime), style: GoogleFonts.robotoMono(color: employeeNavy, fontSize: 12, fontWeight: FontWeight.w700))), const Icon(Icons.arrow_forward_rounded, color: Color(0xFF94A3B8), size: 18), Expanded(child: Text(_formatTimeOfDay(_endTime), textAlign: TextAlign.right, style: GoogleFonts.robotoMono(color: employeeNavy, fontSize: 12, fontWeight: FontWeight.w700)))]))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _timePreset('1 hr (2–3 PM)', const TimeOfDay(hour: 14, minute: 0), const TimeOfDay(hour: 15, minute: 0))),
            const SizedBox(width: 6),
            Expanded(child: _timePreset('2 hrs (2–4 PM)', const TimeOfDay(hour: 14, minute: 0), const TimeOfDay(hour: 16, minute: 0), selected: durationMinutes == 120)),
            const SizedBox(width: 6),
            Expanded(child: _timePreset('Morning (2 hrs)', const TimeOfDay(hour: 9, minute: 30), const TimeOfDay(hour: 11, minute: 30))),
          ]),
        ],
        const SizedBox(height: 16), Text('Reason', style: GoogleFonts.inter(color: employeeNavy, fontSize: 13, fontWeight: FontWeight.w800)), const SizedBox(height: 7),
        Stack(children: [
          TextField(controller: _reasonCtrl, minLines: 3, maxLines: 3, style: GoogleFonts.inter(color: employeeNavy, fontSize: 13), decoration: InputDecoration(hintText: 'Briefly describe the reason...', hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13), filled: true, fillColor: const Color(0xFFF8FAFC), contentPadding: const EdgeInsets.fromLTRB(43, 13, 13, 13), border: outline, enabledBorder: outline, focusedBorder: focusOutline)),
          const Positioned(left: 14, top: 14, child: IgnorePointer(child: Icon(Icons.edit_outlined, color: Color(0xFF0F52BA), size: 18))),
        ]),
        const SizedBox(height: 15), SizedBox(width: double.infinity, height: 48, child: FilledButton.icon(onPressed: _submitting ? null : _submit, icon: _submitting ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send_rounded, size: 18), label: Text(_submitting ? 'Submitting…' : 'Submit Request'), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F52BA), foregroundColor: Colors.white, elevation: 5, shadowColor: const Color(0x550F52BA), shape: const StadiumBorder(), textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800)))),
      ])),
    ]);
  }

  Widget _timePreset(String label, TimeOfDay start, TimeOfDay end, {bool selected = false}) => OutlinedButton(onPressed: () => setState(() { _startTime = start; _endTime = end; _updateTimeText(); }), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8), foregroundColor: selected ? const Color(0xFF0F52BA) : employeeMuted, backgroundColor: selected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC), side: BorderSide(color: selected ? const Color(0xFF0F52BA) : const Color(0xFFE2E8F0)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))), child: Text(label, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 9, height: 1.15, fontWeight: FontWeight.w700)));
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
    final picked = widget.mobile
        ? await showDialog<DateTime>(
            context: context,
            barrierColor: const Color(0x660F172A),
            builder: (_) => _CompactPermissionCalendar(initialDate: _selectedDate),
          )
        : await showDatePicker(
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
    final pickedStart = widget.mobile
        ? await _showCompactTimePicker(_startTime, 'Select start time')
        : await showTimePicker(
            context: context,
            initialTime: _startTime,
            helpText: 'SELECT START TIME',
          );
    if (pickedStart == null || !mounted) return;

    final pickedEnd = widget.mobile
        ? await _showCompactTimePicker(_endTime, 'Select end time')
        : await showTimePicker(
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

  Future<TimeOfDay?> _showCompactTimePicker(TimeOfDay initial, String title) => showDialog<TimeOfDay>(
    context: context,
    barrierColor: const Color(0x660F172A),
    builder: (_) => _CompactPermissionTimePicker(initialTime: initial, title: title),
  );

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

    if (_requestType == 'permission' && _startTime.hour == _endTime.hour && _startTime.minute == _endTime.minute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an end time later than the start time.')),
      );
      return;
    }

    final payload = {
      'type': _requestType,
      'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
      if (_requestType == 'permission') 'start_time': '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
      if (_requestType == 'permission') 'end_time': '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
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
                  DropdownButtonFormField<String>(
                    value: _requestType,
                    decoration: const InputDecoration(labelText: 'Request type', prefixIcon: Icon(Icons.assignment_outlined), border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'permission', child: Text('Permission')),
                      DropdownMenuItem(value: 'attendance_regularization', child: Text('Attendance regularization (app crash)')),
                    ],
                    onChanged: (value) => setState(() => _requestType = value ?? 'permission'),
                  ),
                  const SizedBox(height: 14),
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
                    if (_requestType == 'attendance_regularization') return dateField;
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
