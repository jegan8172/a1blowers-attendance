import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../services/api_config.dart';
import '../../../services/auth_storage.dart';

class LeavePolicyDialog extends StatefulWidget {
  const LeavePolicyDialog({super.key});

  @override
  State<LeavePolicyDialog> createState() => _LeavePolicyDialogState();
}

class _LeavePolicyDialogState extends State<LeavePolicyDialog> {
  static const _blue = Color(0xFF0969F9);
  static const _navy = Color(0xFF101E4A);
  static const _muted = Color(0xFF63729A);
  static const _line = Color(0xFFDDE6F5);

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  final Map<String, TextEditingController> _allowance = {};
  final Map<String, bool> _visible = {};
  final Map<String, String> _displayModes = {};
  final Map<String, bool> _paid = {};
  final Map<String, bool> _halfDay = {};

  static const _order = [
    'Sick Leave',
    'Earned Leave',
    'Casual Leave',
    'Optional Holiday',
  ];

  static const _types = {
    'Sick Leave': _LeaveType('SL', Icons.medical_services_outlined,
        Color(0xFFFFEAED), Color(0xFFFF4B55)),
    'Earned Leave': _LeaveType('EL', Icons.eco_outlined, Color(0xFFDFF7F3),
        Color(0xFF00A887)),
    'Casual Leave': _LeaveType('CL', Icons.beach_access_outlined,
        Color(0xFFE7EEFF), Color(0xFF1769FF)),
    'Optional Holiday': _LeaveType('OH', Icons.calendar_month_outlined,
        Color(0xFFF0E8FF), Color(0xFF834AFF)),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getString('auth_token');
    if (token == null || token.isEmpty) throw Exception('Please sign in again.');
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  dynamic _parse(http.Response response) {
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {}
    if (response.statusCode >= 400 || body is! Map || body['success'] != true) {
      throw Exception(body is Map
          ? body['message'] ?? 'Request failed (${response.statusCode}).'
          : 'Policy service unavailable (${response.statusCode}).');
    }
    return body['data'];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/attendance/leave/policies'),
              headers: await _headers())
          .timeout(const Duration(seconds: 12));
      final data = _parse(response) as List;
      if (!mounted) return;
      for (final controller in _allowance.values) {
        controller.dispose();
      }
      _allowance.clear();
      _visible.clear();
      _displayModes.clear();
      _paid.clear();
      _halfDay.clear();
      _rows = data.map((item) => Map<String, dynamic>.from(item)).toList()
        ..sort((a, b) => _rowOrder(a).compareTo(_rowOrder(b)));
      for (final row in _rows) {
        final id = '${row['id']}';
        final annual = row['annual_allowance'];
        _allowance[id] = TextEditingController(
          text: annual is num ? annual.toStringAsFixed(2) : '$annual',
        );
        _visible[id] = row['employee_card_visible'] == true || row['employee_card_visible'] == 1;
        _displayModes[id] = row['employee_card_display_mode']?.toString() ?? 'Balance & usage';
        _paid[id] = row['payroll_mode']?.toString() == 'paid';
        _halfDay[id] = row['allow_half_day'] == true || row['allow_half_day'] == 1;
      }
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _loading = false);
  }

  int _rowOrder(Map<String, dynamic> row) {
    final value = _order.indexOf('${row['leave_type']}');
    return value == -1 ? _order.length : value;
  }

  _LeaveType _typeFor(Map<String, dynamic> row) =>
      _types['${row['leave_type']}'] ?? _types['Casual Leave']!;

  Future<void> _save() async {
    for (final row in _rows) {
      final value = double.tryParse(_allowance['${row['id']}']!.text);
      if (value == null || value < 0 || value > 366 || value * 2 != (value * 2).roundToDouble()) {
        setState(() => _error =
            'Allowance must be between 0 and 366 in half-day increments.');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final headers = await _headers();
      for (final row in _rows) {
        await _parse(await http
            .put(
              Uri.parse('${ApiConfig.baseUrl}/attendance/leave/policies/${row['id']}'),
              headers: headers,
              body: jsonEncode({
                'annual_allowance': double.parse(_allowance['${row['id']}']!.text),
                'monthly_allowance': row['monthly_allowance'] ?? 0,
                'carry_forward': row['carry_forward'] == 1 || row['carry_forward'] == true,
                'active': row['active'] == 1 || row['active'] == true,
                'employee_card_visible': _visible['${row['id']}'] == true,
                'employee_card_display_mode': _displayModes['${row['id']}'],
                'payroll_mode': _paid['${row['id']}'] == true ? 'paid' : 'unpaid',
                'allow_half_day': _halfDay['${row['id']}'] == true,
              }),
            )
            .timeout(const Duration(seconds: 12)));
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Some changes may have saved. ${error.toString().replaceFirst('Exception: ', '')}';
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _allowance.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _visible.values.where((value) => value).length;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 808),
        child: SizedBox(
          height: 475,
          child: Column(children: [
            _header(count),
            const Divider(height: 1, color: _line),
            Expanded(child: _body()),
            const Divider(height: 1, color: _line),
            _footer(),
          ]),
        ),
      ),
    );
  }

  Widget _header(int count) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 15, 16),
        child: Row(children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Leave Card Settings',
                  style: TextStyle(color: _navy, fontSize: 20, fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text('Set leave balances, paid or unpaid status, and whether each type permits half-day leave.',
                  style: TextStyle(color: _muted, fontSize: 12)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(color: const Color(0xFFEAF1FF), borderRadius: BorderRadius.circular(22)),
            child: Text('$count of ${_rows.length} visible',
                style: const TextStyle(color: _blue, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 9),
          IconButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Color(0xFF66789B), size: 20),
            splashRadius: 20,
          ),
        ]),
      );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _blue));
    if (_error != null && _rows.isEmpty) {
      return Center(child: TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(_error!)));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 14, 0),
      child: Column(children: [
        _tableHeader(),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: _rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: _line),
            itemBuilder: (context, index) => _row(_rows[index]),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(_error!, style: const TextStyle(color: Color(0xFFC62828), fontSize: 11)),
          ),
      ]),
    );
  }

  Widget _tableHeader() => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(color: Color(0xFFF1F5FF), border: Border(bottom: BorderSide(color: _line))),
        child: const Row(children: [
          SizedBox(width: 28),
          Expanded(flex: 23, child: _Label('Leave type')),
          Expanded(flex: 16, child: _Label('Allowance')),
          Expanded(flex: 18, child: _Label('Employee card')),
          Expanded(flex: 21, child: _Label('Display mode')),
          Expanded(flex: 18, child: _Label('Pay / duration')),
        ]),
      );

  Widget _row(Map<String, dynamic> row) {
    final id = '${row['id']}';
    final type = _typeFor(row);
    final visible = _visible[id] ?? false;
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: visible ? Colors.white : const Color(0xFFF7F9FD),
      child: Row(children: [
        const SizedBox(width: 28, child: Icon(Icons.drag_indicator, color: Color(0xFF6980A8), size: 18)),
        Expanded(flex: 23, child: _identity(row, type)),
        Expanded(flex: 16, child: _allowanceField(id)),
        Expanded(flex: 18, child: Align(alignment: Alignment.center, child: _toggle(id, visible))),
        Expanded(flex: 21, child: _displayMode(id)),
        Expanded(flex: 18, child: _chips(id, visible)),
      ]),
    );
  }

  Widget _identity(Map<String, dynamic> row, _LeaveType type) => Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: type.background, shape: BoxShape.circle),
          child: Icon(type.icon, color: type.color, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${row['leave_type']}', overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _navy, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(type.code, style: const TextStyle(color: _muted, fontSize: 10)),
          ],
        )),
      ]);

  Widget _allowanceField(String id) => Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 58,
          height: 28,
          child: TextField(
            controller: _allowance[id],
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: _navy, fontSize: 12),
            decoration: _outline().copyWith(
              suffixIcon: const Icon(Icons.unfold_more, color: _muted, size: 15),
              suffixIconConstraints: const BoxConstraints(minWidth: 18),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text('days', style: TextStyle(color: _muted, fontSize: 11)),
      ]);

  Widget _toggle(String id, bool visible) => Switch(
        value: visible,
        onChanged: _saving ? null : (value) => setState(() => _visible[id] = value),
        activeColor: Colors.white,
        activeTrackColor: _blue,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: const Color(0xFFA9B4C9),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  Widget _displayMode(String id) => SizedBox(
        height: 29,
        child: DropdownButtonFormField<String>(
          value: _displayModes[id],
          isDense: true,
          style: const TextStyle(color: Color(0xFF44516C), fontSize: 10),
          decoration: _outline(),
          items: const [
            DropdownMenuItem(value: 'Usage only', child: Text('Usage only')),
            DropdownMenuItem(value: 'Balance & usage', child: Text('Balance & usage')),
          ],
          onChanged: _saving ? null : (value) => setState(() => _displayModes[id] = value ?? 'Usage only'),
        ),
      );

  InputDecoration _outline() => InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: _line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: _blue)),
      );

  Widget _chips(String id, bool visible) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _policyChip(_paid[id] == true ? '▣  Paid leave' : '⌁  Unpaid (LOP)',
              _paid[id] == true ? const Color(0xFFD9F7E8) : const Color(0xFFFFE8E9),
              _paid[id] == true ? const Color(0xFF00854A) : const Color(0xFFD92934),
              () => setState(() => _paid[id] = !(_paid[id] ?? false))),
          const SizedBox(height: 3),
          _policyChip(_halfDay[id] == true ? '◉  Half day on' : '⊘  Half day off',
              _halfDay[id] == true ? const Color(0xFFEAF2FF) : const Color(0xFFECF0F6),
              _halfDay[id] == true ? _blue : _muted,
              () => setState(() => _halfDay[id] = !(_halfDay[id] ?? false))),
          const SizedBox(height: 3),
          _chip(visible ? '◉  Visible' : '⌧  Hidden',
              visible ? const Color(0xFFD9F7E8) : const Color(0xFFECF0F6),
              visible ? const Color(0xFF00854A) : const Color(0xFF63729A)),
        ],
      );

  Widget _policyChip(String label, Color background, Color color, VoidCallback onTap) => InkWell(
        onTap: _saving ? null : onTap,
        borderRadius: BorderRadius.circular(5),
        child: _chip(label, background, color),
      );

  Widget _chip(String label, Color background, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(5)),
        child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      );

  Widget _footer() => SizedBox(
        height: 61,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            const Icon(Icons.group_outlined, size: 18, color: _muted),
            const SizedBox(width: 10),
            const Text('Changes apply to all active employees', style: TextStyle(color: _muted, fontSize: 12)),
            const Spacer(),
            OutlinedButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: _blue,
                side: const BorderSide(color: Color(0xFF9EBFFF)),
                minimumSize: const Size(72, 34),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 9),
            FilledButton(
              onPressed: _loading || _saving || _rows.isEmpty ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                minimumSize: const Size(104, 34),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
              ),
              child: Text(_saving ? 'Saving...' : 'Save Changes',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.value);
  final String value;

  @override
  Widget build(BuildContext context) => Text(value,
      style: const TextStyle(color: Color(0xFF101E4A), fontSize: 11, fontWeight: FontWeight.w600));
}

class _LeaveType {
  const _LeaveType(this.code, this.icon, this.background, this.color);

  final String code;
  final IconData icon;
  final Color background;
  final Color color;
}
