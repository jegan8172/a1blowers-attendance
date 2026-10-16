import 'package:flutter/material.dart';
import '../../shared/theme/admin_surface_palette.dart';

import '../../shared/widgets/admin_top_nav.dart';
import '../../../../services/hrms_clock_logs_api.dart';

const _blue = Color(0xFFE3162A);
const _navy = Color(0xFF081B3C);
const _page = Color(0xFFF7F8FA);
const _line = Color(0xFFD8E1F0);

class ClockLogsPage extends StatefulWidget {
  const ClockLogsPage({super.key});
  static Widget builder(BuildContext context) => const ClockLogsPage();
  @override
  State<ClockLogsPage> createState() => _ClockLogsPageState();
}

class _MobileClockLogs extends StatelessWidget {
  const _MobileClockLogs({
    required this.searchController,
    required this.logs,
    required this.date,
    required this.monthly,
    required this.loading,
    required this.error,
    required this.onSearch,
    required this.onPeriodChanged,
    required this.onPickDate,
    required this.onRetry,
  });

  final TextEditingController searchController;
  final List<Map<String, dynamic>> logs;
  final DateTime date;
  final bool monthly, loading;
  final String? error;
  final VoidCallback onSearch, onPickDate, onRetry;
  final ValueChanged<bool> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final present = logs.where((item) => _lower(item['status']) == 'present').length;
    final late = logs.where((item) => _lower(item['status']).contains('late')).length;
    final absent = logs.where((item) => _lower(item['status']).contains('absent')).length;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: const AdminMobileBottomNav(activeRoute: '/admin/clock-logs'),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Image.asset('assets/images/a1_blowers_logo_header.png', height: 38),
        actions: const [
          AdminNotificationBell(mobile: true),
          SizedBox(width: 4),
          AdminLogoutButton(compact: true),
          SizedBox(width: 8),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error!, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: onRetry, child: const Text('Retry'))])))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Clock Logs', style: TextStyle(color: _navy, fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    const Text('Track employee attendance and working hours', style: TextStyle(color: Color(0xFF52638E), fontSize: 13)),
                    const SizedBox(height: 16),
                    Row(children: [
                      _MobileMetric(label: 'Records', value: '${logs.length}', color: _blue, background: const Color(0xFFEAF1FF)),
                      const SizedBox(width: 8),
                      _MobileMetric(label: 'Present', value: '$present', color: const Color(0xFF149B2B), background: const Color(0xFFE8F6EA)),
                      const SizedBox(width: 8),
                      _MobileMetric(label: 'Late', value: '$late', color: const Color(0xFFFF6A00), background: const Color(0xFFFFF0E6)),
                      const SizedBox(width: 8),
                      _MobileMetric(label: 'Absent', value: '$absent', color: const Color(0xFFF0182A), background: const Color(0xFFFDEBED)),
                    ]),
                    const SizedBox(height: 16),
                    TextField(
                      controller: searchController,
                      onChanged: (_) => onSearch(),
                      decoration: InputDecoration(
                        hintText: 'Search employee or ID',
                        hintStyle: const TextStyle(color: Color(0xFF50649E)),
                        prefixIcon: const Icon(Icons.search_rounded, color: _navy),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 17),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _blue, width: 1.4)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: _MobilePeriodToggle(monthly: monthly, onChanged: onPeriodChanged)),
                      const SizedBox(width: 10),
                      Expanded(child: OutlinedButton.icon(onPressed: onPickDate, icon: const Icon(Icons.calendar_month_outlined, size: 20), label: Text(monthly ? _monthLabel(date) : _dayLabel(date)), style: OutlinedButton.styleFrom(foregroundColor: _navy, side: const BorderSide(color: _line), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
                    ]),
                    const SizedBox(height: 18),
                    if (logs.isEmpty)
                      const Center(child: Padding(padding: EdgeInsets.all(30), child: Text('No clock logs found for this period.')))
                    else if (searchController.text.trim().isEmpty)
                      _MobileDateHistory(logs: logs)
                    else
                      _MobileEmployeeHistory(logs: logs),
                  ]),
                ),
    );
  }

  static String _lower(dynamic value) => value?.toString().toLowerCase() ?? '';
  static String _monthLabel(DateTime value) => '${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][value.month - 1]} ${value.year}';
  static String _dayLabel(DateTime value) => '${value.day.toString().padLeft(2, '0')} ${_monthLabel(value).split(' ').first} ${value.year}';
}

class _MobileMetric extends StatelessWidget {
  const _MobileMetric({required this.label, required this.value, required this.color, required this.background});
  final String label, value;
  final Color color, background;
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    height: 78,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: color.withValues(alpha: .22)), borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF50649E), fontSize: 11)),
      const Spacer(),
      Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 25)),
    ]),
  ));
}

class _MobilePeriodToggle extends StatelessWidget {
  const _MobilePeriodToggle({required this.monthly, required this.onChanged});
  final bool monthly;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    height: 52,
    decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(12)),
    clipBehavior: Clip.antiAlias,
    child: Row(children: [
      _periodButton('Month', monthly, () => onChanged(true)),
      _periodButton('Day', !monthly, () => onChanged(false)),
    ]),
  );
  Widget _periodButton(String label, bool active, VoidCallback onTap) => Expanded(child: InkWell(onTap: onTap, child: Container(alignment: Alignment.center, color: active ? _blue : Colors.white, child: Text(label, style: TextStyle(color: active ? Colors.white : _navy, fontWeight: FontWeight.w700)))));
}

class _MobileLogCard extends StatelessWidget {
  const _MobileLogCard({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final name = item['employeeName']?.toString() ?? 'Former employee';
    final id = item['staffId']?.toString() ?? item['employeeId']?.toString() ?? 'Unassigned';
    final status = item['status']?.toString() ?? 'Absent';
    final lower = status.toLowerCase();
    final color = lower.contains('absent') ? const Color(0xFFF04438) : lower.contains('late') ? const Color(0xFFFF9200) : const Color(0xFF149B2B);
    final bg = lower.contains('absent') ? const Color(0xFFFFEBEB) : lower.contains('late') ? const Color(0xFFFFF1DB) : const Color(0xFFE9F6EC);
    final minutes = item['workingMinutes'] is int ? item['workingMinutes'] as int : int.tryParse('${item['workingMinutes']}') ?? 0;
    final worked = '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Color(0x08071A72), blurRadius: 12, offset: Offset(0, 4))]),
      child: Column(children: [
        Row(children: [
          CircleAvatar(radius: 22, backgroundColor: const Color(0xFFEAF1FF), child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(color: _navy, fontWeight: FontWeight.w800))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontWeight: FontWeight.w800, fontSize: 15)),
            Text(id, style: const TextStyle(color: Color(0xFF52638E), fontSize: 12)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)), child: Text(_title(status), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _LogTime(label: 'Check in', value: item['checkIn']?.toString() ?? '-'),
          _divider(),
          _LogTime(label: 'Check out', value: item['checkOut']?.toString() ?? '-'),
          _divider(),
          _LogTime(label: 'Worked', value: worked),
        ]),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: Text(item['date']?.toString() ?? '', style: const TextStyle(color: Color(0xFF52638E), fontSize: 11))),
      ]),
    );
  }
  Widget _divider() => Container(width: 1, height: 30, color: _line);
  static String _title(String value) => value.replaceAll('_', ' ').split(' ').map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}').join(' ');
}

class _LogTime extends StatelessWidget {
  const _LogTime({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 7), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Color(0xFF52638E), fontSize: 10)), const SizedBox(height: 3), Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontWeight: FontWeight.w700, fontSize: 12))])));
}

class _MobileDateHistory extends StatelessWidget {
  const _MobileDateHistory({required this.logs});
  final List<Map<String, dynamic>> logs;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final log in logs) {
      final date = log['date']?.toString() ?? 'Unknown date';
      groups.putIfAbsent(date, () => []).add(log);
    }
    final entries = groups.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('All clock logs', style: TextStyle(color: _navy, fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      ...entries.expand((entry) => [
        Padding(padding: const EdgeInsets.only(left: 2, bottom: 7, top: 4), child: Text(_displayDate(entry.key), style: const TextStyle(color: Color(0xFF52638E), fontWeight: FontWeight.w700, fontSize: 13))),
        ...entry.value.map((item) => _MobileDailyLogRow(item: item)),
        const SizedBox(height: 5),
      ]),
    ]);
  }

  static String _displayDate(String raw) {
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }
}

class _MobileEmployeeHistory extends StatelessWidget {
  const _MobileEmployeeHistory({required this.logs});
  final List<Map<String, dynamic>> logs;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final log in logs) {
      final key = log['staffId']?.toString() ?? log['employeeId']?.toString() ?? log['employeeName']?.toString() ?? 'unknown';
      groups.putIfAbsent(key, () => []).add(log);
    }
    return Column(children: groups.values.map((records) => _MobileEmployeeHistoryCard(records: records)).toList());
  }
}

class _MobileEmployeeHistoryCard extends StatelessWidget {
  const _MobileEmployeeHistoryCard({required this.records});
  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) {
    final first = records.first;
    final name = first['employeeName']?.toString() ?? 'Former employee';
    final id = first['staffId']?.toString() ?? first['employeeId']?.toString() ?? 'Unassigned';
    final present = records.where((item) => (item['status']?.toString().toLowerCase() ?? '') == 'present').length;
    final late = records.where((item) => (item['status']?.toString().toLowerCase() ?? '').contains('late')).length;
    final absent = records.where((item) => (item['status']?.toString().toLowerCase() ?? '').contains('absent')).length;
    final sorted = [...records]..sort((a, b) => (b['date']?.toString() ?? '').compareTo(a['date']?.toString() ?? ''));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 23, backgroundColor: const Color(0xFFEAF1FF), child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(color: _navy, fontWeight: FontWeight.w800, fontSize: 18))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontSize: 16, fontWeight: FontWeight.w800)),
            Text(id, style: const TextStyle(color: Color(0xFF52638E), fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _HistoryCount(label: 'Present', value: present, color: const Color(0xFF149B2B)),
          const SizedBox(width: 8),
          _HistoryCount(label: 'Late', value: late, color: const Color(0xFFFF6A00)),
          const SizedBox(width: 8),
          _HistoryCount(label: 'Absent', value: absent, color: const Color(0xFFF0182A)),
        ]),
        const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider(height: 1, color: _line)),
        const Text('Attendance history', style: TextStyle(color: _navy, fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        ...sorted.map((item) => _MobileHistoryRow(item: item)),
      ]),
    );
  }
}

class _HistoryCount extends StatelessWidget {
  const _HistoryCount({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7), decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(9)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Color(0xFF52638E), fontSize: 10)), Text('$value', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18))])));
}

class _MobileDailyLogRow extends StatelessWidget {
  const _MobileDailyLogRow({required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) {
    final name = item['employeeName']?.toString() ?? 'Former employee';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Row(children: [
          CircleAvatar(radius: 18, backgroundColor: const Color(0xFFEAF1FF), child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(color: _navy, fontWeight: FontWeight.w800))),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _navy, fontWeight: FontWeight.w800)), Text(item['staffId']?.toString() ?? item['employeeId']?.toString() ?? '', style: const TextStyle(color: Color(0xFF52638E), fontSize: 11))])),
          _StatusBadge(status: item['status']?.toString() ?? 'Absent'),
        ]),
        const SizedBox(height: 10),
        _ClockValues(item: item),
      ]),
    );
  }
}

class _MobileHistoryRow extends StatelessWidget {
  const _MobileHistoryRow({required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
    child: Column(children: [
      Row(children: [Expanded(child: Text(_MobileDateHistory._displayDate(item['date']?.toString() ?? ''), style: const TextStyle(color: _navy, fontWeight: FontWeight.w700, fontSize: 13))), _StatusBadge(status: item['status']?.toString() ?? 'Absent')]),
      const SizedBox(height: 9),
      _ClockValues(item: item),
    ]),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final lower = status.toLowerCase();
    final color = lower.contains('absent') ? const Color(0xFFF04438) : lower.contains('late') ? const Color(0xFFFF9200) : const Color(0xFF149B2B);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(15)), child: Text(_MobileLogCard._title(status), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)));
  }
}

class _ClockValues extends StatelessWidget {
  const _ClockValues({required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) {
    final minutes = item['workingMinutes'] is int ? item['workingMinutes'] as int : int.tryParse('${item['workingMinutes']}') ?? 0;
    final worked = '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
    return Row(children: [
      _LogTime(label: 'Check in', value: item['checkIn']?.toString() ?? '-'),
      Container(width: 1, height: 28, color: _line),
      _LogTime(label: 'Check out', value: item['checkOut']?.toString() ?? '-'),
      Container(width: 1, height: 28, color: _line),
      _LogTime(label: 'Worked', value: worked),
    ]);
  }
}

class _ClockLogsPageState extends State<ClockLogsPage> {
  final _employeeSearchController = TextEditingController();
  DateTime _date = DateTime.now();
  bool _monthly = true;
  int? _employeeId;
  List<Map<String, dynamic>> _employees = const [];
  List<Map<String, dynamic>> _logs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _employeeSearchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _visibleLogs {
    final query = _employeeSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return _logs;
    return _logs.where((item) {
      final name = item['employeeName']?.toString().toLowerCase() ?? '';
      final id = item['staffId']?.toString().toLowerCase() ?? item['employeeId']?.toString().toLowerCase() ?? '';
      return name.contains(query) || id.contains(query);
    }).toList();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await HrmsClockLogsApi.list(date: _date, monthly: _monthly, employeeId: _employeeId);
      if (!mounted) return;
      setState(() {
        _employees = (data['employees'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _logs = (data['items'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() { _loading = false; _error = error.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _pickDate() async {
    final chosen = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (chosen != null) { setState(() => _date = chosen); _load(); }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 600) {
      return _MobileClockLogs(
        searchController: _employeeSearchController,
        logs: _visibleLogs,
        date: _date,
        monthly: _monthly,
        loading: _loading,
        error: _error,
        onSearch: () => setState(() {}),
        onPeriodChanged: (monthly) {
          if (_monthly != monthly) {
            setState(() => _monthly = monthly);
            _load();
          }
        },
        onPickDate: _pickDate,
        onRetry: _load,
      );
    }
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 600 ? const AdminMobileBottomNav(activeRoute: '/admin/clock-logs') : null,
      body: Column(children: [
        const AdminTopNav(activeRoute: '/admin/clock-logs'),
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(narrow ? 16 : 38, 18, narrow ? 16 : 38, 28),
          child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1900),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!narrow) ...[
                const AdminPageHeader(title: 'Employee Clock Logs', breadcrumb: 'Clock Logs'),
                const SizedBox(height: 8),
              ],
              Text('Review employee check-in and check-out records from attendance data.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15)),
              const SizedBox(height: 18),
              _summary(),
              const SizedBox(height: 18),
              _filters(narrow),
              const SizedBox(height: 23),
              if (_loading) const Center(child: Padding(padding: EdgeInsets.all(42), child: CircularProgressIndicator()))
              else if (_error != null) _message(_error!, retry: _load)
              else _table(),
            ]),
          )),
        )),
      ]),
    );
  }

  Widget _filters(bool narrow) {
    final palette = AdminSurfacePalette.of(context);
    return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [BoxShadow(color: Color(0x0C071A72), blurRadius: 18, offset: Offset(0, 6))],
    ),
    child: Wrap(spacing: 18, runSpacing: 14, crossAxisAlignment: WrapCrossAlignment.end, children: [
        SizedBox(
          width: narrow ? double.infinity : 430,
          child: TextField(
            controller: _employeeSearchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by name, employee ID or email',
              hintStyle: TextStyle(color: palette.mutedText, fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, color: palette.text),
              filled: true,
              fillColor: palette.subtleSurface,
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _blue),
              ),
            ),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('View', style: TextStyle(color: palette.text, fontSize: 13)), const SizedBox(height: 7), _toggle()]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Date', style: TextStyle(color: palette.text, fontSize: 13)), const SizedBox(height: 7), OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_month_outlined), label: Text(_monthly ? _monthLabel(_date) : _dayLabel(_date)), style: _fieldStyle())]),
    ]),
  );
  }

  Widget _summary() {
    final logs = _visibleLogs;
    final present = logs.where((item) => item['status']?.toString().toLowerCase() == 'present').length;
    final late = logs.where((item) => item['status']?.toString().toLowerCase().contains('late') == true).length;
    final absent = logs.where((item) => item['status']?.toString().toLowerCase().contains('absent') == true).length;
    
    return LayoutBuilder(builder: (_, constraints) {
      final columns = 4;
      final spacing = constraints.maxWidth < 700 ? 8.0 : 16.0;
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: 8,
        children: [
          SizedBox(width: width, child: _compactMetric('Records', logs.length, _blue)),
          SizedBox(width: width, child: _compactMetric('Present', present, const Color(0xFF149B2B))),
          SizedBox(width: width, child: _compactMetric('Late', late, const Color(0xFFFF6A00))),
          SizedBox(width: width, child: _compactMetric('Absent', absent, const Color(0xFFF0182A))),
        ],
      );
    });
  }

  Widget _compactMetric(String label, int value, Color color) {
    final palette = AdminSurfacePalette.of(context);
    return Container(
    height: 80,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: palette.surface, border: Border.all(color: color.withValues(alpha: .25)), borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.mutedText, fontSize: 11)),
      const Spacer(),
      Text('$value', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 25)),
    ]),
  );
  }

  Widget _metric(String label, int value, String subtitle, IconData icon, Color color, [Color background = const Color(0xFFEAF1FF)]) {
    final palette = AdminSurfacePalette.of(context);
    return Container(
    height: 116,
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 9),
    decoration: BoxDecoration(
      color: palette.surface,
      border: Border.all(color: color.withValues(alpha: 0.28)),
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [
        BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4)),
      ],
    ),
    child: Column(
      children: [
        Row(children: [
          Container(width: 54, height: 54, decoration: BoxDecoration(color: background, shape: BoxShape.circle), child: Icon(icon, color: color, size: 29)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.text, fontSize: 13)),
            const SizedBox(height: 3),
            Text('$value', style: TextStyle(color: palette.text, fontSize: 27, fontWeight: FontWeight.w700)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.mutedText, fontSize: 11)),
          ])),
        ]),
        const Spacer(),
        Align(alignment: Alignment.centerLeft, child: Container(width: 55, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)))),
      ],
    ),
  );
  }

  Widget _toggle() => Container(
    decoration: BoxDecoration(border: Border.all(color: const Color(0xFF777B86)), borderRadius: BorderRadius.circular(23)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      _toggleButton('Day', !_monthly), _toggleButton('Month', _monthly),
    ]),
  );
  
  Widget _toggleButton(String label, bool active) => InkWell(
    onTap: () { final monthly = label == 'Month'; if (_monthly != monthly) { setState(() => _monthly = monthly); _load(); } },
    borderRadius: BorderRadius.circular(22),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10), decoration: BoxDecoration(color: active ? const Color(0xFFE2E6FA) : Colors.white, borderRadius: BorderRadius.circular(22)), child: Row(mainAxisSize: MainAxisSize.min, children: [if (active) const Padding(padding: EdgeInsets.only(right: 7), child: Icon(Icons.check, size: 18)), Text(label, style: const TextStyle(fontSize: 16))])),
  );
  
  ButtonStyle _fieldStyle() => OutlinedButton.styleFrom(foregroundColor: const Color(0xFF273754), side: const BorderSide(color: _line), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), textStyle: const TextStyle(fontSize: 16));

  Widget _table() => LayoutBuilder(
    builder: (_, constraints) {
      final tableWidth = constraints.maxWidth < 1300 ? 1300.0 : constraints.maxWidth;
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(color: AdminSurfacePalette.of(context).surface, border: Border.all(color: AdminSurfacePalette.of(context).border), borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                _row(const ['Employee', 'Date', 'Check In', 'Check Out', 'Worked', 'Extra Hours', 'Status', 'Method', 'Reasons'], header: true),
                if (_visibleLogs.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Text('No clock logs found for the selected period.')),
                ..._visibleLogs.map(_logRow),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _logRow(Map<String, dynamic> item) {
    final name = item['employeeName']?.toString() ?? 'Former employee';
    final staffId = item['staffId']?.toString() ?? item['employeeId']?.toString() ?? 'Unassigned';
    final reasons = [
      if (item['clockOutReason']?.toString().trim().isNotEmpty == true) 'Clock out: ${item['clockOutReason']}',
      if (item['trackingStopReason']?.toString().trim().isNotEmpty == true) 'Tracking: ${item['trackingStopReason']}',
    ].join('\n');
    return _row([_employeeCell(name, staffId), item['date']?.toString() ?? '-', item['checkIn']?.toString() ?? '-', item['checkOut']?.toString() ?? '-', _worked(item['workingMinutes']), _overtimeButton(item), _status(item['status']?.toString() ?? 'Absent'), item['method']?.toString() ?? '-', reasons.isEmpty ? '—' : reasons]);
  }

  Widget _overtimeButton(Map<String, dynamic> item) {
    final minutes = _asInt(item['overtimeMinutes']);
    if (minutes == 0) return const Text('—');
    return TextButton(onPressed: () async {
      try {
        final rows = await HrmsClockLogsApi.overtimeHistory(_asInt(item['employeeId']));
        if (!mounted) return;
        await showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('Overtime history'), content: SizedBox(width: 430, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: rows.map((row) => ListTile(title: Text('${row['attendance_date']}'), trailing: Text(_worked(row['overtime_minutes'])))).toList()))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]));
      } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')))); }
    }, child: Text(_worked(minutes)));
  }

  Widget _row(List<dynamic> values, {bool header = false}) => Container(
    height: header ? 58 : 80,
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
    child: Row(
      children: List.generate(values.length, (i) => Expanded(
        flex: const [22, 12, 12, 12, 11, 12, 13, 11, 22][i],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: values[i] is Widget ? values[i] : Text(
              '${values[i]}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: header ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: header ? 14 : 14,
                fontWeight: header ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      )),
    ),
  );
  
  Widget _employeeCell(String name, String id) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Row(children: [
      Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: Color(0xFFEAF0FA), shape: BoxShape.circle),
        child: Text(initial, style: const TextStyle(color: _navy, fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      const SizedBox(width: 16),
      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
        const SizedBox(height: 3),
        Text(id, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
      ])),
    ]);
  }
  
  Widget _status(String value) { 
    final lower = value.toLowerCase(); 
    final color = lower.contains('absent') ? const Color(0xFFF04438) : lower.contains('late') ? const Color(0xFFFF9200) : const Color(0xFF3BB95A); 
    final bg = lower.contains('absent') ? const Color(0xFFFFEBEB) : lower.contains('late') ? const Color(0xFFFFF1DB) : const Color(0xFFE9F6EC); 
    
    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        value.replaceAll('_', ' ').split(' ').map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}').join(' '), 
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
      ),
    ); 
  }
  
  Widget _message(String text, {required VoidCallback retry}) => Center(child: Padding(padding: const EdgeInsets.all(42), child: Column(children: [Text(text), const SizedBox(height: 12), OutlinedButton(onPressed: retry, child: const Text('Retry'))])));
  
  int _asInt(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;
  String _worked(dynamic minutes) { final value = _asInt(minutes); return '${value ~/ 60}h ${(value % 60).toString().padLeft(2, '0')}m'; }
  String _monthLabel(DateTime date) => '${const ['January','February','March','April','May','June','July','August','September','October','November','December'][date.month - 1]} ${date.year}';
  String _dayLabel(DateTime date) => '${date.day.toString().padLeft(2, '0')} ${_monthLabel(date).split(' ').first} ${date.year}';
}
