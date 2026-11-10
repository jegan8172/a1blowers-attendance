import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../shared/theme/admin_surface_palette.dart';

import '../../shared/widgets/admin_top_nav.dart';
import '../../../../services/hrms_clock_logs_api.dart';

const _blue = Color(0xFF1769E0);
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
    final present = logs
        .where((item) => _lower(item['status']) == 'present')
        .length;
    final late = logs
        .where((item) => _lower(item['status']).contains('late'))
        .length;
    final absent = logs
        .where((item) => _clockStatus(item) == 'Missing out')
        .length;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: const AdminMobileBottomNav(
        activeRoute: '/admin/clock-logs',
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Image.asset(
          'assets/images/a1_blowers_logo_header.png',
          height: 38,
        ),
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
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Clock Logs',
                    style: TextStyle(
                      color: _navy,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Track employee attendance and working hours',
                    style: TextStyle(color: Color(0xFF52638E), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _MobileMetric(
                        label: 'Records',
                        value: '${logs.length}',
                        color: _blue,
                        background: const Color(0xFFEAF1FF),
                      ),
                      const SizedBox(width: 8),
                      _MobileMetric(
                        label: 'Present',
                        value: '$present',
                        color: const Color(0xFF149B2B),
                        background: const Color(0xFFE8F6EA),
                      ),
                      const SizedBox(width: 8),
                      _MobileMetric(
                        label: 'Late',
                        value: '$late',
                        color: const Color(0xFFFF6A00),
                        background: const Color(0xFFFFF0E6),
                      ),
                      const SizedBox(width: 8),
                      _MobileMetric(
                        label: 'Missing out',
                        value: '$absent',
                        color: const Color(0xFFF0182A),
                        background: const Color(0xFFFDEBED),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchController,
                    onChanged: (_) => onSearch(),
                    decoration: InputDecoration(
                      hintText: 'Search employee or ID',
                      hintStyle: const TextStyle(color: Color(0xFF50649E)),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: _navy,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 17),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _blue, width: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MobilePeriodToggle(
                          monthly: monthly,
                          onChanged: onPeriodChanged,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onPickDate,
                          icon: const Icon(
                            Icons.calendar_month_outlined,
                            size: 20,
                          ),
                          label: Text(
                            monthly ? _monthLabel(date) : _dayLabel(date),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _navy,
                            side: const BorderSide(color: _line),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 15,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (logs.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(30),
                        child: Text('No clock logs found for this period.'),
                      ),
                    )
                  else if (searchController.text.trim().isEmpty)
                    _MobileDateHistory(logs: logs)
                  else
                    _MobileEmployeeHistory(logs: logs),
                ],
              ),
            ),
    );
  }

  static String _lower(dynamic value) => value?.toString().toLowerCase() ?? '';
  static String _monthLabel(DateTime value) =>
      '${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][value.month - 1]} ${value.year}';
  static String _dayLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')} ${_monthLabel(value).split(' ').first} ${value.year}';
}

class _MobileMetric extends StatelessWidget {
  const _MobileMetric({
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });
  final String label, value;
  final Color color, background;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 78,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color.withValues(alpha: .22)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF50649E), fontSize: 11),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 25,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MobilePeriodToggle extends StatelessWidget {
  const _MobilePeriodToggle({required this.monthly, required this.onChanged});
  final bool monthly;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    height: 52,
    decoration: BoxDecoration(
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: Row(
      children: [
        _periodButton('Month', monthly, () => onChanged(true)),
        _periodButton('Day', !monthly, () => onChanged(false)),
      ],
    ),
  );
  Widget _periodButton(String label, bool active, VoidCallback onTap) =>
      Expanded(
        child: InkWell(
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            color: active ? _blue : Colors.white,
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : _navy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
}

class _MobileLogCard extends StatelessWidget {
  const _MobileLogCard({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final name = item['employeeName']?.toString() ?? 'Former employee';
    final id =
        item['staffId']?.toString() ??
        item['employeeId']?.toString() ??
        'Unassigned';
    final status = item['status']?.toString() ?? 'Absent';
    final lower = status.toLowerCase();
    final color =
        lower.contains('absent') ||
            lower.contains('missing') ||
            lower.contains('early')
        ? const Color(0xFFF04438)
        : lower.contains('late')
        ? const Color(0xFFFF9200)
        : const Color(0xFF149B2B);
    final bg = lower.contains('absent')
        ? const Color(0xFFFFEBEB)
        : lower.contains('late')
        ? const Color(0xFFFFF1DB)
        : const Color(0xFFE9F6EC);
    final minutes = item['workingMinutes'] is int
        ? item['workingMinutes'] as int
        : int.tryParse('${item['workingMinutes']}') ?? 0;
    final worked =
        '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08071A72),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFEAF1FF),
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(
                    color: _navy,
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
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      id,
                      style: const TextStyle(
                        color: Color(0xFF52638E),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _title(status),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _LogTime(
                label: 'Check in',
                value: item['checkIn']?.toString() ?? '-',
              ),
              _divider(),
              _LogTime(
                label: 'Check out',
                value: item['checkOut']?.toString() ?? '-',
              ),
              _divider(),
              _LogTime(label: 'Worked', value: worked),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              item['date']?.toString() ?? '',
              style: const TextStyle(color: Color(0xFF52638E), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 30, color: _line);
  static String _title(String value) => value
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

class _LogTime extends StatelessWidget {
  const _LogTime({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF52638E), fontSize: 10),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _navy,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );
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
    final entries = groups.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'All clock logs',
          style: TextStyle(
            color: _navy,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        ...entries.expand(
          (entry) => [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 7, top: 4),
              child: Text(
                _displayDate(entry.key),
                style: const TextStyle(
                  color: Color(0xFF52638E),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            ...entry.value.map((item) => _MobileDailyLogRow(item: item)),
            const SizedBox(height: 5),
          ],
        ),
      ],
    );
  }

  static String _displayDate(String raw) {
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    const months = [
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
      final key =
          log['staffId']?.toString() ??
          log['employeeId']?.toString() ??
          log['employeeName']?.toString() ??
          'unknown';
      groups.putIfAbsent(key, () => []).add(log);
    }
    return Column(
      children: groups.values
          .map((records) => _MobileEmployeeHistoryCard(records: records))
          .toList(),
    );
  }
}

class _MobileEmployeeHistoryCard extends StatelessWidget {
  const _MobileEmployeeHistoryCard({required this.records});
  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) {
    final first = records.first;
    final name = first['employeeName']?.toString() ?? 'Former employee';
    final id =
        first['staffId']?.toString() ??
        first['employeeId']?.toString() ??
        'Unassigned';
    final present = records
        .where(
          (item) =>
              (item['status']?.toString().toLowerCase() ?? '') == 'present',
        )
        .length;
    final late = records
        .where(
          (item) =>
              (item['status']?.toString().toLowerCase() ?? '').contains('late'),
        )
        .length;
    final absent = records
        .where(
          (item) => (item['status']?.toString().toLowerCase() ?? '').contains(
            'absent',
          ),
        )
        .length;
    final sorted = [...records]
      ..sort(
        (a, b) => (b['date']?.toString() ?? '').compareTo(
          a['date']?.toString() ?? '',
        ),
      );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: const Color(0xFFEAF1FF),
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      id,
                      style: const TextStyle(
                        color: Color(0xFF52638E),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _HistoryCount(
                label: 'Present',
                value: present,
                color: const Color(0xFF149B2B),
              ),
              const SizedBox(width: 8),
              _HistoryCount(
                label: 'Late',
                value: late,
                color: const Color(0xFFFF6A00),
              ),
              const SizedBox(width: 8),
              _HistoryCount(
                label: 'Absent',
                value: absent,
                color: const Color(0xFFF0182A),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: _line),
          ),
          const Text(
            'Attendance history',
            style: TextStyle(
              color: _navy,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          ...sorted.map((item) => _MobileHistoryRow(item: item)),
        ],
      ),
    );
  }
}

class _HistoryCount extends StatelessWidget {
  const _HistoryCount({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF52638E), fontSize: 10),
          ),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ],
      ),
    ),
  );
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
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFEAF1FF),
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      item['staffId']?.toString() ??
                          item['employeeId']?.toString() ??
                          '',
                      style: const TextStyle(
                        color: Color(0xFF52638E),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: item['status']?.toString() ?? 'Absent'),
            ],
          ),
          const SizedBox(height: 10),
          _ClockValues(item: item),
        ],
      ),
    );
  }
}

class _MobileHistoryRow extends StatelessWidget {
  const _MobileHistoryRow({required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _MobileDateHistory._displayDate(item['date']?.toString() ?? ''),
                style: const TextStyle(
                  color: _navy,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            _StatusBadge(status: item['status']?.toString() ?? 'Absent'),
          ],
        ),
        const SizedBox(height: 9),
        _ClockValues(item: item),
      ],
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final lower = status.toLowerCase();
    final color =
        lower.contains('absent') ||
            lower.contains('missing') ||
            lower.contains('early')
        ? const Color(0xFFF04438)
        : lower.contains('late')
        ? const Color(0xFFFF9200)
        : const Color(0xFF149B2B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        _MobileLogCard._title(status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ClockValues extends StatelessWidget {
  const _ClockValues({required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) {
    final minutes = item['workingMinutes'] is int
        ? item['workingMinutes'] as int
        : int.tryParse('${item['workingMinutes']}') ?? 0;
    final worked =
        '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
    return Row(
      children: [
        _LogTime(label: 'Check in', value: item['checkIn']?.toString() ?? '-'),
        Container(width: 1, height: 28, color: _line),
        _LogTime(
          label: 'Check out',
          value: item['checkOut']?.toString() ?? '-',
        ),
        Container(width: 1, height: 28, color: _line),
        _LogTime(label: 'Worked', value: worked),
      ],
    );
  }
}

class _ClockLogsPageState extends State<ClockLogsPage> {
  final _employeeSearchController = TextEditingController();
  DateTime _date = DateTime.now();
  bool _monthly = false;
  int? _employeeId;
  List<Map<String, dynamic>> _employees = const [];
  List<Map<String, dynamic>> _logs = const [];
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

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
      final id =
          item['staffId']?.toString().toLowerCase() ??
          item['employeeId']?.toString().toLowerCase() ??
          '';
      final role = item['role']?.toString().toLowerCase() ?? '';
      return name.contains(query) || id.contains(query) || role.contains(query);
    }).toList();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await HrmsClockLogsApi.list(
        date: _date,
        monthly: _monthly,
        employeeId: _employeeId,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _employees = (data['employees'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _logs = (data['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration)
        setState(() {
          _loading = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  Future<void> _pickDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (chosen != null) {
      setState(() => _date = chosen);
      _load();
    }
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          const AdminTopNav(activeRoute: '/admin/clock-logs'),
          Expanded(
            child: _ClockWorkspace(
              logs: _visibleLogs,
              employees: _employees,
              search: _employeeSearchController,
              loading: _loading,
              error: _error,
              period: _monthly ? _monthLabel(_date) : _dayLabel(_date),
              monthly: _monthly,
              onSearch: () => setState(() {}),
              onPickDate: _pickDate,
              onPreviousDate: () {
                setState(() => _date = _date.subtract(const Duration(days: 1)));
                _load();
              },
              onNextDate: () {
                setState(() => _date = _date.add(const Duration(days: 1)));
                _load();
              },
              onPeriod: (monthly) {
                if (_monthly != monthly) {
                  setState(() => _monthly = monthly);
                  _load();
                }
              },
              onRetry: _load,
            ),
          ),
        ],
      ),
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
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C071A72),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('View', style: TextStyle(color: palette.text, fontSize: 13)),
              const SizedBox(height: 7),
              _toggle(),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Date', style: TextStyle(color: palette.text, fontSize: 13)),
              const SizedBox(height: 7),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(_monthly ? _monthLabel(_date) : _dayLabel(_date)),
                style: _fieldStyle(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    final logs = _visibleLogs;
    final present = logs
        .where((item) => item['status']?.toString().toLowerCase() == 'present')
        .length;
    final late = logs
        .where(
          (item) =>
              item['status']?.toString().toLowerCase().contains('late') == true,
        )
        .length;
    final absent = logs
        .where(
          (item) =>
              item['status']?.toString().toLowerCase().contains('absent') ==
              true,
        )
        .length;

    return LayoutBuilder(
      builder: (_, constraints) {
        final columns = 4;
        final spacing = constraints.maxWidth < 700 ? 8.0 : 16.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: 8,
          children: [
            SizedBox(
              width: width,
              child: _compactMetric('Records', logs.length, _blue),
            ),
            SizedBox(
              width: width,
              child: _compactMetric(
                'Present',
                present,
                const Color(0xFF149B2B),
              ),
            ),
            SizedBox(
              width: width,
              child: _compactMetric('Late', late, const Color(0xFFFF6A00)),
            ),
            SizedBox(
              width: width,
              child: _compactMetric('Absent', absent, const Color(0xFFF0182A)),
            ),
          ],
        );
      },
    );
  }

  Widget _compactMetric(String label, int value, Color color) {
    final palette = AdminSurfacePalette.of(context);
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
            '$value',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(
    String label,
    int value,
    String subtitle,
    IconData icon,
    Color color, [
    Color background = const Color(0xFFEAF1FF),
  ]) {
    final palette = AdminSurfacePalette.of(context);
    return Container(
      height: 116,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 9),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 29),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.text, fontSize: 13),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$value',
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.mutedText, fontSize: 11),
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
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle() => Container(
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFF777B86)),
      borderRadius: BorderRadius.circular(23),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _toggleButton('Day', !_monthly),
        _toggleButton('Month', _monthly),
      ],
    ),
  );

  Widget _toggleButton(String label, bool active) => InkWell(
    onTap: () {
      final monthly = label == 'Month';
      if (_monthly != monthly) {
        setState(() => _monthly = monthly);
        _load();
      }
    },
    borderRadius: BorderRadius.circular(22),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE2E6FA) : Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active)
            const Padding(
              padding: EdgeInsets.only(right: 7),
              child: Icon(Icons.check, size: 18),
            ),
          Text(label, style: const TextStyle(fontSize: 16)),
        ],
      ),
    ),
  );

  ButtonStyle _fieldStyle() => OutlinedButton.styleFrom(
    foregroundColor: const Color(0xFF273754),
    side: const BorderSide(color: _line),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    textStyle: const TextStyle(fontSize: 16),
  );

  Widget _table() => LayoutBuilder(
    builder: (_, constraints) {
      final tableWidth = constraints.maxWidth < 1300
          ? 1300.0
          : constraints.maxWidth;
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AdminSurfacePalette.of(context).surface,
          border: Border.all(color: AdminSurfacePalette.of(context).border),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                _row(const [
                  'Employee',
                  'Date',
                  'Check In',
                  'Check Out',
                  'Worked',
                  'Extra Hours',
                  'Status',
                  'Method',
                  'Reasons',
                ], header: true),
                if (_visibleLogs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('No clock logs found for the selected period.'),
                  ),
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
    final staffId =
        item['staffId']?.toString() ??
        item['employeeId']?.toString() ??
        'Unassigned';
    final reasons = [
      if (item['clockOutReason']?.toString().trim().isNotEmpty == true)
        'Clock out: ${item['clockOutReason']}',
      if (item['trackingStopReason']?.toString().trim().isNotEmpty == true)
        'Tracking: ${item['trackingStopReason']}',
    ].join('\n');
    return _row([
      _employeeCell(name, staffId),
      item['date']?.toString() ?? '-',
      item['checkIn']?.toString() ?? '-',
      item['checkOut']?.toString() ?? '-',
      _worked(item['workingMinutes']),
      _overtimeButton(item),
      _status(item['status']?.toString() ?? 'Absent'),
      item['method']?.toString() ?? '-',
      reasons.isEmpty ? '—' : reasons,
    ]);
  }

  Widget _overtimeButton(Map<String, dynamic> item) {
    final minutes = _asInt(item['overtimeMinutes']);
    if (minutes == 0) return const Text('—');
    return TextButton(
      onPressed: () async {
        try {
          final rows = await HrmsClockLogsApi.overtimeHistory(
            _asInt(item['employeeId']),
          );
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Overtime history'),
              content: SizedBox(
                width: 430,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: rows
                        .map(
                          (row) => ListTile(
                            title: Text('${row['attendance_date']}'),
                            trailing: Text(_worked(row['overtime_minutes'])),
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
      },
      child: Text(_worked(minutes)),
    );
  }

  Widget _row(List<dynamic> values, {bool header = false}) => Container(
    height: header ? 58 : 80,
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: Row(
      children: List.generate(
        values.length,
        (i) => Expanded(
          flex: const [22, 12, 12, 12, 11, 12, 13, 11, 22][i],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: values[i] is Widget
                  ? values[i]
                  : Text(
                      '${values[i]}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: header
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: header ? 14 : 14,
                        fontWeight: header ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _employeeCell(String name, String id) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFEAF0FA),
            shape: BoxShape.circle,
          ),
          child: Text(
            initial,
            style: const TextStyle(
              color: _navy,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _status(String value) {
    final lower = value.toLowerCase();
    final color = lower.contains('absent')
        ? const Color(0xFFF04438)
        : lower.contains('late')
        ? const Color(0xFFFF9200)
        : const Color(0xFF3BB95A);
    final bg = lower.contains('absent')
        ? const Color(0xFFFFEBEB)
        : lower.contains('late')
        ? const Color(0xFFFFF1DB)
        : const Color(0xFFE9F6EC);

    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        value
            .replaceAll('_', ' ')
            .split(' ')
            .map(
              (p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}',
            )
            .join(' '),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _message(String text, {required VoidCallback retry}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(42),
      child: Column(
        children: [
          Text(text),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: retry, child: const Text('Retry')),
        ],
      ),
    ),
  );

  int _asInt(dynamic value) =>
      value is int ? value : int.tryParse('$value') ?? 0;
  String _worked(dynamic minutes) {
    final value = _asInt(minutes);
    return '${value ~/ 60}h ${(value % 60).toString().padLeft(2, '0')}m';
  }

  String _monthLabel(DateTime date) =>
      '${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][date.month - 1]} ${date.year}';
  String _dayLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')} ${_monthLabel(date).split(' ').first} ${date.year}';
}

String _clockStatus(Map<String, dynamic> log) {
  final out = '${log['checkOut'] ?? ''}'.trim();
  if (out.isEmpty || out == '-' || out == '—') {
    final date = '${log['date'] ?? ''}'.trim();
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return date == today ? 'Active' : 'Missing out';
  }
  final status = '${log['status'] ?? ''}'.toLowerCase();
  if (status.contains('late')) return 'Late';
  if (status.contains('early')) return 'Early exit';
  return status == 'present'
      ? 'On time'
      : (log['status']?.toString() ?? 'Unknown');
}

String _clockHours(Iterable<Map<String, dynamic>> logs) {
  final minutes = logs.fold<int>(
    0,
    (sum, log) => sum + (int.tryParse('${log['workingMinutes'] ?? 0}') ?? 0),
  );
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

class _ClockWorkspace extends StatefulWidget {
  const _ClockWorkspace({
    required this.logs,
    required this.employees,
    required this.search,
    required this.loading,
    required this.error,
    required this.period,
    required this.monthly,
    required this.onSearch,
    required this.onPickDate,
    required this.onPreviousDate,
    required this.onNextDate,
    required this.onPeriod,
    required this.onRetry,
  });
  final List<Map<String, dynamic>> logs, employees;
  final TextEditingController search;
  final bool loading, monthly;
  final String? error;
  final String period;
  final VoidCallback onSearch, onPickDate, onPreviousDate, onNextDate, onRetry;
  final ValueChanged<bool> onPeriod;
  @override
  State<_ClockWorkspace> createState() => _ClockWorkspaceState();
}

class _ClockWorkspaceState extends State<_ClockWorkspace> {
  String status = 'All statuses';
  String role = 'All designations';
  int page = 0;
  String? selectedId;
  static const perPage = 10;

  Future<void> _showRemarks(Map<String, dynamic> log) async {
    final id = '${log['id']}';
    final controller = TextEditingController();
    var remarksFuture = HrmsClockLogsApi.remarks(id);
    var saving = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Clock Log Remarks'),
              content: SizedBox(
                width: 440,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: remarksFuture,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) return const Text('Unable to load remarks.');
                      if (!snapshot.hasData) return const CircularProgressIndicator();
                      final items = snapshot.data!;
                      if (items.isEmpty) return const Text('No remarks yet.');
                      return SizedBox(height: 180, child: ListView(
                        children: items.map((item) => ListTile(
                          title: Text('${item['remark'] ?? ''}'),
                          subtitle: Text('Admin ${item['adminUserId']} · ${item['createdAt']}'),
                        )).toList(),
                      ));
                    },
                  )),
                  const SizedBox(height: 12),
                  TextField(controller: controller, maxLength: 1000, maxLines: 3,
                    decoration: const InputDecoration(labelText: 'New remark', border: OutlineInputBorder())),
                ]),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
                FilledButton(onPressed: saving ? null : () async {
                  final remark = controller.text.trim();
                  if (remark.length < 3) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter at least 3 characters.')));
                    return;
                  }
                  setDialogState(() => saving = true);
                  try {
                    await HrmsClockLogsApi.addRemark(id, remark);
                    if (dialogContext.mounted) {
                      controller.clear();
                      setDialogState(() {
                        remarksFuture = HrmsClockLogsApi.remarks(id);
                      });
                    }
                  } catch (error) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
                  } finally {
                    if (dialogContext.mounted) setDialogState(() => saving = false);
                  }
                }, child: Text(saving ? 'Saving…' : 'Save Remark')),
              ],
            );
          },
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _export(List<Map<String, dynamic>> logs) async {
    if (logs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No clock logs to export.')));
      return;
    }
    try {
      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (context) => [
            pw.Text(
              'Clock logs - ${widget.period}',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: [
                'Employee',
                'Employee ID',
                'Designation',
                'Date',
                'Check in',
                'Check out',
                'Worked',
                'Status',
              ],
              data: logs
                  .map(
                    (log) => [
                      '${log['employeeName'] ?? '-'}',
                      '${log['staffId'] ?? '-'}',
                      '${log['role'] ?? '-'}',
                      '${log['date'] ?? '-'}',
                      '${log['checkIn'] ?? '-'}',
                      '${log['checkOut'] ?? '-'}',
                      _clockHours([log]),
                      _clockStatus(log),
                    ],
                  )
                  .toList(),
            ),
          ],
        ),
      );
      await Printing.layoutPdf(
        name: 'clock-logs.pdf',
        onLayout: (_) => doc.save(),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to export clock logs. Please try again.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles =
        widget.logs
            .map((e) => '${e['role'] ?? ''}'.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final activeRole = roles.contains(role) ? role : 'All designations';
    final filtered = widget.logs
        .where(
          (e) =>
              (status == 'All statuses' || _clockStatus(e) == status) &&
              (activeRole == 'All designations' ||
                  '${e['role'] ?? ''}' == activeRole),
        )
        .toList();
    final pages = filtered.isEmpty ? 1 : (filtered.length / perPage).ceil();
    final current = page.clamp(0, pages - 1);
    final shown = filtered.skip(current * perPage).take(perPage).toList();
    final selected = filtered
        .where((e) => '${e['id']}' == selectedId)
        .firstOrNull;
    final missing = filtered
        .where((e) => _clockStatus(e) == 'Missing out')
        .length;
    final exceptions = filtered
        .where(
          (e) =>
              ['Late', 'Early exit', 'Missing out'].contains(_clockStatus(e)),
        )
        .length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1050;
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final count = box.maxWidth < 900 ? 2 : 5;
                  final width = (box.maxWidth - (count - 1) * 12) / count;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _metric(
                        width,
                        'Total Clock Ins',
                        '${filtered.length}',
                        Icons.login,
                        const Color(0xFF009D69),
                      ),
                      _metric(
                        width,
                        'Total Clock Outs',
                        '${filtered.length - missing}',
                        Icons.logout,
                        _blue,
                      ),
                      _metric(
                        width,
                        'Active Employees',
                        '${widget.employees.length}',
                        Icons.people_outline,
                        const Color(0xFF1675D1),
                      ),
                      _metric(
                        width,
                        'Exceptions',
                        '$exceptions',
                        Icons.warning_amber_rounded,
                        const Color(0xFFE58A00),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              if (widget.loading)
                const Padding(
                  padding: EdgeInsets.all(60),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (widget.error != null)
                _surface(
                  child: Center(
                    child: Column(
                      children: [
                        Text(widget.error!),
                        TextButton(
                          onPressed: widget.onRetry,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _surface(
                          padding: EdgeInsets.zero,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: LayoutBuilder(
                                    builder: (context, toolbar) {
                                    final controls = <Widget>[
                                      _filterGroup(
                                        'Date',
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: 'Previous date',
                                              onPressed: widget.onPreviousDate,
                                              icon: const Icon(Icons.chevron_left),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed: widget.onPickDate,
                                              style: OutlinedButton.styleFrom(
                                                minimumSize: const Size(0, 38),
                                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                              ),
                                              icon: const Icon(Icons.calendar_month_outlined, size: 18),
                                              label: Text(widget.period),
                                            ),
                                            IconButton(
                                              tooltip: 'Next date',
                                              onPressed: widget.onNextDate,
                                              icon: const Icon(Icons.chevron_right),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _filterGroup(
                                        'Search',
                                        TextField(
                                          controller: widget.search,
                                          onChanged: (_) {
                                            setState(() => page = 0);
                                            widget.onSearch();
                                          },
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            prefixIcon: Icon(Icons.search),
                                            hintText: 'Search employee or ID',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      _filterGroup(
                                        'Status',
                                        _dropdown(
                                          status,
                                          [
                                            'All statuses',
                                            'On time',
                                            'Late',
                                            'Early exit',
                                            'Missing out',
                                          ],
                                          (v) => setState(() {
                                            status = v;
                                            page = 0;
                                          }),
                                        ),
                                      ),
                                      _filterGroup(
                                        'Designation',
                                        _dropdown(
                                          activeRole,
                                          ['All designations', ...roles],
                                          (v) => setState(() {
                                            role = v;
                                            page = 0;
                                          }),
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(0, 38),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                        ),
                                        onPressed:
                                            widget.loading ||
                                                widget.error != null
                                            ? null
                                            : () => _export(filtered),
                                        icon: const Icon(
                                          Icons.download_outlined,
                                        ),
                                        label: const Text('Export'),
                                      ),
                                    ];
                                    const gap = SizedBox(width: 12);
                                    if (toolbar.maxWidth >= 1180) {
                                      return Row(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          controls[0], gap,
                                          Expanded(child: controls[1]), gap,
                                          controls[2], gap,
                                          controls[3], gap,
                                          controls[4],
                                        ],
                                      );
                                    }
                                    if (toolbar.maxWidth >= 700) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              controls[0], gap,
                                              Expanded(child: controls[1]),
                                              const SizedBox(width: 12),
                                              controls[4],
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Expanded(child: controls[2]), gap,
                                              controls[3], gap, controls[4],
                                            ],
                                          ),
                                        ],
                                      );
                                    }
                                    return Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      crossAxisAlignment: WrapCrossAlignment.end,
                                      children: [
                                        controls[0],
                                        SizedBox(width: toolbar.maxWidth, child: controls[1]),
                                        controls[4],
                                        SizedBox(width: toolbar.maxWidth, child: controls[2]),
                                        controls[3],
                                      ],
                                    );
                                    },
                                  ),
                                ),
                              ),
                              const Divider(height: 1, color: _line),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 14,
                                  children: [
                                    Text(
                                      'Clock Logs (${widget.period})',
                                      style: const TextStyle(
                                        color: _navy,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '${filtered.length} logs',
                                      style: const TextStyle(
                                        color: Color(0xFF52638E),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      LayoutBuilder(
                                        builder: (context, tableConstraints) => SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: SizedBox(
                                            width: tableConstraints.maxWidth
                                                .clamp(850.0, double.infinity),
                                            child: DataTable(
                                              showCheckboxColumn: false,
                                              headingRowColor:
                                                  WidgetStateProperty.all(
                                                    const Color(0xFFF3F6FA),
                                                  ),
                                              horizontalMargin: 14,
                                              columnSpacing: 16,
                                              headingRowHeight: 44,
                                              dataRowMinHeight: 42,
                                              dataRowMaxHeight: 48,
                                              columns: const [
                                                DataColumn(label: Text('S.No.')),
                                                DataColumn(
                                                  label: Text('Employee'),
                                                ),
                                                DataColumn(
                                                  label: Text('Designation'),
                                                ),
                                                DataColumn(label: Text('Date')),
                                                DataColumn(
                                                  label: Text('Check in'),
                                                ),
                                                DataColumn(
                                                  label: Text('Check out'),
                                                ),
                                                DataColumn(
                                                  label: Text('Worked'),
                                                ),
                                                DataColumn(
                                                  label: Text('Status'),
                                                ),
                                              ],
                                              rows: shown.asMap().entries
                                                  .map(
                                                    (entry) {
                                                      final log = entry.value;
                                                      return DataRow(
                                                      selected:
                                                          '${log['id']}' ==
                                                          selectedId,
                                                      onSelectChanged: (_) {
                                                        if (compact) {
                                                          showDialog<void>(
                                                            context: context,
                                                            builder: (context) => Dialog(
                                                              child: SizedBox(
                                                                width: 400,
                                                                height:
                                                                    MediaQuery.sizeOf(
                                                                      context,
                                                                    ).height *
                                                                    .85,
                                                                child: LayoutBuilder(
                                                                  builder:
                                                                      (
                                                                        context,
                                                                        panel,
                                                                      ) => FittedBox(
                                                                        fit: BoxFit
                                                                            .scaleDown,
                                                                        alignment:
                                                                            Alignment.topCenter,
                                                                        child: SizedBox(
                                                                          width:
                                                                              panel.maxWidth,
                                                                          child: _details(
                                                                            log,
                                                                            () => Navigator.pop(
                                                                              context,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                ),
                                                              ),
                                                            ),
                                                          );
                                                        } else {
                                                          setState(
                                                            () => selectedId =
                                                                '${log['id']}',
                                                          );
                                                        }
                                                      },
                                                      cells: [
                                                        DataCell(Text('${current * perPage + entry.key + 1}')),
                                                        DataCell(Text('${log['employeeName'] ?? '-'}')),
                                                        DataCell(
                                                          Text(
                                                            '${log['role'] ?? '-'}',
                                                          ),
                                                        ),
                                                        DataCell(
                                                          Text(
                                                            '${log['date'] ?? '-'}',
                                                          ),
                                                        ),
                                                        DataCell(
                                                          Text(
                                                            '${log['checkIn'] ?? '-'}',
                                                          ),
                                                        ),
                                                        DataCell(
                                                          Text(
                                                            '${log['checkOut'] ?? '-'}',
                                                          ),
                                                        ),
                                                        DataCell(
                                                          Text(
                                                            _clockHours([log]),
                                                          ),
                                                        ),
                                                        DataCell(
                                                          _StatusBadge(
                                                            status:
                                                                _clockStatus(
                                                                  log,
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                    },
                                                  )
                                                  .toList(),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (filtered.isEmpty)
                                        const Padding(
                                          padding: EdgeInsets.all(28),
                                          child: Center(
                                            child: Text(
                                              'No clock logs found for the selected filters.',
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        filtered.isEmpty
                                            ? 'No logs'
                                            : 'Showing ${current * perPage + 1}–${current * perPage + shown.length} of ${filtered.length} logs',
                                        style: const TextStyle(
                                          color: Color(0xFF52638E),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: current > 0
                                          ? () => setState(
                                              () => page = current - 1,
                                            )
                                          : null,
                                      icon: const Icon(Icons.chevron_left),
                                    ),
                                    Text('${current + 1} / $pages'),
                                    IconButton(
                                      onPressed: current + 1 < pages
                                          ? () => setState(
                                              () => page = current + 1,
                                            )
                                          : null,
                                      icon: const Icon(Icons.chevron_right),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedContainer(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 280),
                        curve: Curves.easeInOutCubic,
                        width: selected != null && !compact
                            ? (constraints.maxWidth * .32).clamp(380.0, 600.0) + 14
                            : 0,
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.centerRight,
                            minWidth: (constraints.maxWidth * .32).clamp(380.0, 600.0),
                            maxWidth: (constraints.maxWidth * .32).clamp(380.0, 600.0),
                            child: LayoutBuilder(
                              builder: (context, panel) => SingleChildScrollView(
                                child: AnimatedSwitcher(
                                  duration: MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 220),
                                  transitionBuilder: (child, animation) => FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0.025, 0),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                                  child: selected == null || compact
                                      ? const SizedBox.shrink(key: ValueKey('empty'))
                                      : ConstrainedBox(
                                          key: ValueKey(selectedId),
                                          constraints: BoxConstraints(
                                            minHeight: panel.maxHeight,
                                            minWidth: panel.maxWidth,
                                          ),
                                          child: _details(
                                            selected,
                                            () => setState(() => selectedId = null),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _surface({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
  Widget _filterGroup(String label, Widget control) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: _navy,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 5),
      control,
    ],
  );
  Widget _metric(
    double width,
    String label,
    String value,
    IconData icon,
    Color color,
  ) => SizedBox(
    width: width,
    child: _surface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: color.withValues(alpha: .1),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF52638E),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.loading || widget.error != null ? '—' : value,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _dropdown(
    String value,
    List<String> values,
    ValueChanged<String> onChanged,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(8),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        isDense: true,
        value: value,
        items: values
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    ),
  );
  Widget _details(Map<String, dynamic> log, VoidCallback close) => _surface(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Log Details',
                style: TextStyle(
                  color: _navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(onPressed: close, icon: const Icon(Icons.close)),
          ],
        ),
        const Divider(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: const Color(0xFFFFE9EC),
              child: Text(
                '${log['employeeName'] ?? '?'}'.isEmpty
                    ? '?'
                    : '${log['employeeName'] ?? '?'}'[0].toUpperCase(),
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${log['employeeName'] ?? 'Employee'}',
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${log['role'] ?? '-'}',
                    style: const TextStyle(color: Color(0xFF52638E)),
                  ),
                  Text(
                    'Emp ID: ${log['staffId'] ?? '-'}',
                    style: const TextStyle(color: Color(0xFF52638E)),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formattedDate(log['date']),
                  style: const TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _formattedDate(log['date'], weekday: true),
                  style: const TextStyle(
                    color: Color(0xFF52638E),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        const Divider(height: 20),
        const Text(
          'Clock Timeline',
          style: TextStyle(
            color: _navy,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        _timelineEntry(
          'Check in',
          '${log['checkIn'] ?? '-'}',
          '${log['method'] ?? '-'}',
          log['checkInLatitude'],
          log['checkInLongitude'],
        ),
        _timelineEntry(
          'Check out',
          '${log['checkOut'] ?? '-'}',
          '${log['method'] ?? '-'}',
          log['checkOutLatitude'],
          log['checkOutLongitude'],
        ),
        const Divider(height: 20),
        const Text(
          'Exception Review',
          style: TextStyle(
            color: _navy,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              _clockStatus(log) == 'On time' ? Icons.check_circle : Icons.info,
              size: 20,
              color: _clockStatus(log) == 'On time'
                  ? const Color(0xFF00A66C)
                  : const Color(0xFFE58A00),
            ),
            const SizedBox(width: 8),
            Text(
              _clockStatus(log),
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _clockStatus(log) == 'On time'
                ? const Color(0xFFE6F8EF)
                : const Color(0xFFFFF5E6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Worked: ${_clockHours([log])}',
                style: const TextStyle(color: _navy),
              ),
              if ('${log['clockOutReason'] ?? ''}'.trim().isNotEmpty)
                _detailRow('Clock out reason', '${log['clockOutReason']}'),
              if ('${log['trackingStopReason'] ?? ''}'.trim().isNotEmpty)
                _detailRow(
                  'Tracking stop reason',
                  '${log['trackingStopReason']}',
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.calendar_month_outlined, size: 16, color: _navy),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      log['scheduledShiftStart'] == null || log['scheduledShiftEnd'] == null
                          ? 'Scheduled shift: unavailable'
                          : 'Scheduled shift: ${log['scheduledShiftStart']} – ${log['scheduledShiftEnd']}',
                      style: const TextStyle(color: Color(0xFF52638E), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _showRemarks(log),
              icon: const Icon(Icons.chat_bubble_outline, size: 17),
              label: const Text('Add Remark'),
            ),
            OutlinedButton.icon(
              onPressed: '${log['staffId'] ?? ''}'.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pushNamed(
                      '/admin/employees',
                      arguments: {'employeeCode': '${log['staffId']}'},
                    ),
              icon: const Icon(Icons.person_outline, size: 17),
              label: const Text('View Employee'),
            ),
          ],
        ),
      ],
    ),
  );
  Widget _timelineEntry(String label, String time, String method, dynamic latitude, dynamic longitude) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.circle, size: 14, color: Color(0xFF00A66C)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: _navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(time, style: const TextStyle(color: _navy, fontSize: 16)),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 15,
                    color: Color(0xFF52638E),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      latitude == null || longitude == null
                          ? 'Location unavailable'
                          : '$latitude, $longitude',
                      style: const TextStyle(color: Color(0xFF52638E), fontSize: 12),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 19, top: 3),
                child: Text(
                  'Method: $method',
                  style: const TextStyle(
                    color: Color(0xFF52638E),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  String _formattedDate(dynamic value, {bool weekday = false}) {
    final date = DateTime.tryParse('${value ?? ''}');
    if (date == null) return weekday ? '' : '${value ?? '-'}';
    return DateFormat(weekday ? 'EEE' : 'MMM d, y').format(date);
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFF52638E))),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(color: _navy),
          ),
        ),
      ],
    ),
  );
}
