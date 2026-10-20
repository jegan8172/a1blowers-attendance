import 'package:flutter/material.dart';

import '../../../../services/hrms_attendance_time_api.dart';

const _blue = Color(0xFFE3162A);
const _navy = Color(0xFF081B3C);
const _line = Color(0xFFD9E2F1);
const _softBlue = Color(0xFFF1F6FF);
const _muted = Color(0xFF63718F);
const _orange = Color(0xFFFF6A00);
const _red = Color(0xFFD7193F);

Future<void> showManageTimeDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: const Color(0x9907163E),
  builder: (_) => const ManageTimeDialog(),
);

class ManageTimeDialog extends StatefulWidget {
  const ManageTimeDialog({super.key});

  @override
  State<ManageTimeDialog> createState() => _ManageTimeDialogState();
}

class _ManageTimeDialogState extends State<ManageTimeDialog> {
  String _checkIn = '09:30';
  String _checkOut = '18:30';
  String _lateAfter = '10:00';
  String _absentAfter = '12:00';
  String _femaleCheckIn = '09:30';
  String _femaleCheckOut = '18:30';
  String _femaleLateAfter = '10:00';
  String _femaleAbsentAfter = '12:00';
  String _labourLunchStart = '12:30';
  String _labourLunchEnd = '13:00';
  String _employeeLunchStart = '12:30';
  String _employeeLunchEnd = '13:00';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await HrmsAttendanceTimeApi.load();
      if (!mounted) return;
      setState(() {
        final male = values['male'] is Map ? Map<String, dynamic>.from(values['male']) : values;
        final female = values['female'] is Map ? Map<String, dynamic>.from(values['female']) : male;
        _checkIn = _shortTime(male['shiftStart'], fallback: _checkIn);
        _checkOut = _shortTime(male['shiftEnd'], fallback: _checkOut);
        _lateAfter = _shortTime(male['lateAfter'], fallback: _lateAfter);
        _absentAfter = _shortTime(
          male['absentAfter'],
          fallback: _absentAfter,
        );
        _femaleCheckIn = _shortTime(female['shiftStart'], fallback: _femaleCheckIn);
        _femaleCheckOut = _shortTime(female['shiftEnd'], fallback: _femaleCheckOut);
        _femaleLateAfter = _shortTime(female['lateAfter'], fallback: _femaleLateAfter);
        _femaleAbsentAfter = _shortTime(female['absentAfter'], fallback: _femaleAbsentAfter);
        _labourLunchStart = _shortTime(values['labourLunchStart'], fallback: _labourLunchStart);
        _labourLunchEnd = _shortTime(values['labourLunchEnd'], fallback: _labourLunchEnd);
        _employeeLunchStart = _shortTime(values['employeeLunchStart'], fallback: _employeeLunchStart);
        _employeeLunchEnd = _shortTime(values['employeeLunchEnd'], fallback: _employeeLunchEnd);
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load attendance times: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _shortTime(dynamic value, {required String fallback}) {
    final text = value?.toString() ?? '';
    return RegExp(r'^([01]\d|2[0-3]):[0-5]\d').hasMatch(text)
        ? text.substring(0, 5)
        : fallback;
  }

  TimeOfDay _timeOf(String value) {
    final parts = value.split(':').map(int.parse).toList();
    return TimeOfDay(hour: parts[0], minute: parts[1]);
  }

  Future<void> _pickTime({
    required String current,
    required ValueChanged<String> onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOf(current),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: _blue),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    onPicked(
      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await HrmsAttendanceTimeApi.save(
        male: {'shiftStart': _checkIn, 'shiftEnd': _checkOut, 'lateAfter': _lateAfter, 'absentAfter': _absentAfter},
        female: {'shiftStart': _femaleCheckIn, 'shiftEnd': _femaleCheckOut, 'lateAfter': _femaleLateAfter, 'absentAfter': _femaleAbsentAfter},
        labourLunchStart: _labourLunchStart,
        labourLunchEnd: _labourLunchEnd,
        employeeLunchStart: _employeeLunchStart,
        employeeLunchEnd: _employeeLunchEnd,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance time settings saved.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save attendance times: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 620;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 20),
          child: _loading
              ? const SizedBox(
                  height: 250,
                  child: Center(child: CircularProgressIndicator()),
                )
              : SingleChildScrollView(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            color: _softBlue,
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.schedule_rounded, color: _blue),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Manage time',
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                  color: _navy,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Set gender schedules and lunch rules.',
                                style: TextStyle(color: _muted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, color: _muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _softBlue,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFCFE0FC)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MALE WORKING HOURS',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: .8,
                              color: _muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          compact
                              ? Column(
                                  children: [
                                    _timeTile(
                                      icon: Icons.login_rounded,
                                      label: 'Check in',
                                      value: _checkIn,
                                      onTap: () => _pickTime(
                                        current: _checkIn,
                                        onPicked: (value) =>
                                            setState(() => _checkIn = value),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    _timeTile(
                                      icon: Icons.logout_rounded,
                                      label: 'Check out',
                                      value: _checkOut,
                                      onTap: () => _pickTime(
                                        current: _checkOut,
                                        onPicked: (value) =>
                                            setState(() => _checkOut = value),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(
                                      child: _timeTile(
                                        icon: Icons.login_rounded,
                                        label: 'Check in',
                                        value: _checkIn,
                                        onTap: () => _pickTime(
                                          current: _checkIn,
                                          onPicked: (value) =>
                                              setState(() => _checkIn = value),
                                        ),
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Icon(
                                        Icons.arrow_forward_rounded,
                                        color: _muted,
                                      ),
                                    ),
                                    Expanded(
                                      child: _timeTile(
                                        icon: Icons.logout_rounded,
                                        label: 'Check out',
                                        value: _checkOut,
                                        onTap: () => _pickTime(
                                          current: _checkOut,
                                          onPicked: (value) =>
                                              setState(() => _checkOut = value),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _timeTile(
                      icon: Icons.notifications_active_outlined,
                      iconColor: _orange,
                      label: 'Late check-in rule',
                      value: _lateAfter,
                      trailing: 'Mark late after',
                      onTap: () => _pickTime(
                        current: _lateAfter,
                        onPicked: (value) => setState(() => _lateAfter = value),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _timeTile(
                      icon: Icons.person_off_outlined,
                      iconColor: _red,
                      label: 'Absent check-in rule',
                      value: _absentAfter,
                      trailing: 'Mark absent after',
                      onTap: () => _pickTime(
                        current: _absentAfter,
                        onPicked: (value) =>
                            setState(() => _absentAfter = value),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: _softBlue, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFCFE0FC))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('FEMALE WORKING HOURS', style: TextStyle(fontSize: 11, letterSpacing: .8, color: _muted, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        compact
                            ? Column(
                                children: [
                                  _timeTile(icon: Icons.login_rounded, label: 'Check in', value: _femaleCheckIn, onTap: () => _pickTime(current: _femaleCheckIn, onPicked: (v) => setState(() => _femaleCheckIn = v))),
                                  const SizedBox(height: 10),
                                  _timeTile(icon: Icons.logout_rounded, label: 'Check out', value: _femaleCheckOut, onTap: () => _pickTime(current: _femaleCheckOut, onPicked: (v) => setState(() => _femaleCheckOut = v))),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: _timeTile(icon: Icons.login_rounded, label: 'Check in', value: _femaleCheckIn, onTap: () => _pickTime(current: _femaleCheckIn, onPicked: (v) => setState(() => _femaleCheckIn = v)))),
                                  const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.arrow_forward_rounded, color: _muted)),
                                  Expanded(child: _timeTile(icon: Icons.logout_rounded, label: 'Check out', value: _femaleCheckOut, onTap: () => _pickTime(current: _femaleCheckOut, onPicked: (v) => setState(() => _femaleCheckOut = v)))),
                                ],
                              ),
                        const SizedBox(height: 10),
                        _timeTile(icon: Icons.notifications_active_outlined, iconColor: _orange, label: 'Late check-in rule', value: _femaleLateAfter, trailing: 'Mark late after', onTap: () => _pickTime(current: _femaleLateAfter, onPicked: (v) => setState(() => _femaleLateAfter = v))),
                        const SizedBox(height: 10),
                        _timeTile(icon: Icons.person_off_outlined, iconColor: _red, label: 'Absent check-in rule', value: _femaleAbsentAfter, trailing: 'Mark absent after', onTap: () => _pickTime(current: _femaleAbsentAfter, onPicked: (v) => setState(() => _femaleAbsentAfter = v))),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8EE),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFD9A8)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('FIXED LUNCH TIME RULES', style: TextStyle(fontSize: 11, letterSpacing: .8, color: _muted, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 5),
                          const Text('Employees can start lunch only within their assigned time window.', style: TextStyle(color: _muted, fontSize: 12)),
                          const SizedBox(height: 12),
                          _timeTile(icon: Icons.construction_outlined, label: 'Labour lunch start', value: _labourLunchStart, onTap: () => _pickTime(current: _labourLunchStart, onPicked: (value) => setState(() => _labourLunchStart = value))),
                          const SizedBox(height: 10),
                          _timeTile(icon: Icons.construction_outlined, label: 'Labour lunch end', value: _labourLunchEnd, onTap: () => _pickTime(current: _labourLunchEnd, onPicked: (value) => setState(() => _labourLunchEnd = value))),
                          const SizedBox(height: 10),
                          _timeTile(icon: Icons.person_outline_rounded, label: 'Employee lunch start', value: _employeeLunchStart, onTap: () => _pickTime(current: _employeeLunchStart, onPicked: (value) => setState(() => _employeeLunchStart = value))),
                          const SizedBox(height: 10),
                          _timeTile(icon: Icons.person_outline_rounded, label: 'Employee lunch end', value: _employeeLunchEnd, onTap: () => _pickTime(current: _employeeLunchEnd, onPicked: (value) => setState(() => _employeeLunchEnd = value))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Changes apply to future employee check-ins only.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: _blue,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(_saving ? 'Saving...' : 'Save changes'),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
        ),
      ),
    );
  }

  Widget _timeTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    Color iconColor = _blue,
    String? trailing,
  }) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              Text(
                trailing,
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.edit_outlined, size: 18, color: _blue),
          ],
        ),
      ),
    ),
  );
}
