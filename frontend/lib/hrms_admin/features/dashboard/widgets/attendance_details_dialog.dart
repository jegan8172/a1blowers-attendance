import 'package:flutter/material.dart';

import '../../../../services/hrms_clock_logs_api.dart';

class AttendanceDetailsDialog extends StatefulWidget {
  const AttendanceDetailsDialog({super.key, required this.employeeId, required this.date});
  final int employeeId;
  final DateTime date;

  @override
  State<AttendanceDetailsDialog> createState() => _AttendanceDetailsDialogState();
}

class _AttendanceDetailsDialogState extends State<AttendanceDetailsDialog> {
  late Future<Map<String, dynamic>> _details;
  @override
  void initState() { super.initState(); _reload(); }
  void _reload() => _details = HrmsClockLogsApi.attendanceDetails(employeeId: widget.employeeId, date: widget.date);

  String _minutes(dynamic value) {
    final total = value is int ? value : int.tryParse('$value') ?? 0;
    return total == 0 ? '—' : '${total ~/ 60}h ${total % 60}m';
  }
  String _time(dynamic value) {
    if (value == null || '$value'.isEmpty) return '—';
    final date = DateTime.tryParse('$value'.replaceFirst(' ', 'T'));
    if (date == null) return '$value';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    return '${hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
  }
  String get _dateLabel {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[widget.date.month - 1]} ${widget.date.day}, ${widget.date.year}';
  }
  String get _weekday => const ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][widget.date.weekday - 1];

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _details,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            _header(context, data?['status']?.toString() ?? 'Absent'),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: snapshot.connectionState != ConnectionState.done
                ? const SizedBox(height: 210, child: Center(child: CircularProgressIndicator()))
                : snapshot.hasError
                  ? SizedBox(height: 210, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Could not load attendance details.'), const SizedBox(height: 10),
                      OutlinedButton.icon(onPressed: () => setState(_reload), icon: const Icon(Icons.refresh), label: const Text('Retry')),
                    ])))
                  : _content(data!),
            ),
            const Divider(height: 1),
            Align(alignment: Alignment.centerRight, child: Padding(
              padding: const EdgeInsets.all(12), child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            )),
          ]);
        },
      ),
    ),
  );

  Widget _header(BuildContext context, String? status) => Container(
    width: double.infinity, padding: const EdgeInsets.fromLTRB(20, 17, 14, 16),
    decoration: const BoxDecoration(borderRadius: BorderRadius.vertical(top: Radius.circular(25)), gradient: LinearGradient(colors: [Color(0xFF10379C), Color(0xFF176BEE)])),
    child: Row(children: [
      const Icon(Icons.calendar_month_outlined, color: Colors.white, size: 30), const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_dateLabel, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
        Text(_weekday, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
        if (status != null) Padding(padding: const EdgeInsets.only(top: 8), child: _status(status)),
      ])),
      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
    ]),
  );

  Widget _status(String value) => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)), child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)));
  Widget _content(Map<String, dynamic> data) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('ATTENDANCE RECORD', style: TextStyle(color: Color(0xFF60759B), fontWeight: FontWeight.w800, fontSize: 12)), const SizedBox(height: 9),
    GridView.count(crossAxisCount: 2, shrinkWrap: true, childAspectRatio: 2.6, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, children: [
      _card('Check In', _time(data['checkInAt']), const Color(0xFF009A4E)), _card('Check Out', _time(data['checkOutAt']), const Color(0xFF112354)),
      _card('Working Hours', _minutes(data['workingMinutes']), const Color(0xFF176BEE)), _card('Break Time', _minutes(data['breakMinutes']), const Color(0xFFE48016)),
    ]),
    if (data['workMode'] != null || data['checkInLocation'] != null || data['checkOutLocation'] != null) ...[
      const SizedBox(height: 16), const Text('WORK DETAILS', style: TextStyle(color: Color(0xFF60759B), fontWeight: FontWeight.w800, fontSize: 12)), const SizedBox(height: 6),
      Text('Mode: ${data['workMode'] ?? '—'}', style: const TextStyle(color: Color(0xFF364B6D))),
      if (data['checkInLocation'] != null) Text('Check-in location: ${data['checkInLocation']['latitude']}, ${data['checkInLocation']['longitude']}', style: const TextStyle(color: Color(0xFF364B6D))),
      if (data['checkOutLocation'] != null) Text('Check-out location: ${data['checkOutLocation']['latitude']}, ${data['checkOutLocation']['longitude']}', style: const TextStyle(color: Color(0xFF364B6D))),
    ],
    const SizedBox(height: 16), const Text('BREAK RECORD', style: TextStyle(color: Color(0xFF60759B), fontWeight: FontWeight.w800, fontSize: 12)), const SizedBox(height: 9),
    if ((data['breaks'] as List? ?? []).isEmpty)
      _emptyBreak()
    else
      ...(data['breaks'] as List)
          .whereType<Map>()
          .map((item) => _break(Map<String, dynamic>.from(item))),
  ]);
  Widget _card(String label, String value, Color color) => Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: const Color(0xFFF3F6FF), border: Border.all(color: const Color(0xFFD7E1F4)), borderRadius: BorderRadius.circular(13)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(label, style: const TextStyle(color: Color(0xFF687A9B), fontSize: 12, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800))]));
  Widget _emptyBreak() => Container(width: double.infinity, padding: const EdgeInsets.all(20), alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFF3F6FF), border: Border.all(color: const Color(0xFFD7E1F4)), borderRadius: BorderRadius.circular(13)), child: const Text('No break recorded for this day', style: TextStyle(color: Color(0xFF687A9B))));
  Widget _break(Map<String, dynamic> item) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFF7F9FE), borderRadius: BorderRadius.circular(10)), child: Text('${_time(item['startedAt'])} – ${_time(item['endedAt'])}  •  ${_minutes(item['durationMinutes'])}${item['reason'] == null ? '' : '\n${item['reason']}'}'));
}
