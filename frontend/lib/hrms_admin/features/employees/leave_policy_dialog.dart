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
  bool loading = true, saving = false;
  String? error;
  final form = GlobalKey<FormState>();
  List<Map<String, dynamic>> rows = [];
  final Map<String, TextEditingController> fields = {};
  @override
  void initState() { super.initState(); load(); }
  Future<Map<String, String>> headers() async {
    final token = await AuthStorage.getString('auth_token');
    if (token == null || token.isEmpty) throw Exception('Please sign in again.');
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }
  dynamic parse(http.Response response) {
    dynamic body;
    try { body = jsonDecode(response.body); } catch (_) {}
    if (response.statusCode >= 400 || body is! Map || body['success'] != true) {
      throw Exception(body is Map ? body['message'] ?? 'Request failed (${response.statusCode}).' : 'Policy service unavailable (${response.statusCode}).');
    }
    return body['data'];
  }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/attendance/leave/policies'), headers: await headers()).timeout(const Duration(seconds: 12));
      final data = parse(response) as List;
      if (!mounted) return;
      for (final c in fields.values) { c.dispose(); }
      fields.clear();
      rows = data.map((r) => Map<String, dynamic>.from(r)).toList();
      for (final r in rows) { fields['${r['id']}'] = TextEditingController(text: '${r['annual_allowance']}'); }
    } catch (e) { if (mounted) error = e.toString().replaceFirst('Exception: ', ''); }
    if (mounted) setState(() { loading = false; });
  }
  Future<void> save() async {
    if (!(form.currentState?.validate() ?? false)) return;
    setState(() { saving = true; error = null; });
    try {
      final h = await headers();
      for (final r in rows) {
        parse(await http.put(Uri.parse('${ApiConfig.baseUrl}/attendance/leave/policies/${r['id']}'), headers: h, body: jsonEncode({
          'annual_allowance': double.parse(fields['${r['id']}']!.text),
          'carry_forward': r['carry_forward'] == 1 || r['carry_forward'] == true,
          'active': r['active'] == 1 || r['active'] == true,
        })).timeout(const Duration(seconds: 12)));
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) setState(() { error = 'Some changes may have saved. ${e.toString().replaceFirst('Exception: ', '')}'; saving = false; }); }
  }
  @override
  void dispose() { for (final c in fields.values) { c.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Leave Policy · ${DateTime.now().year}'),
    content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (loading) const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator())),
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      if (!loading && rows.isEmpty) TextButton(onPressed: load, child: const Text('No policies loaded. Retry')),
      if (!loading) ...rows.map((r) => Padding(padding: const EdgeInsets.only(top: 16), child: TextFormField(
        controller: fields['${r['id']}'], enabled: !saving,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: '${r['leave_type']}', suffixText: 'days / year', border: const OutlineInputBorder()),
        validator: (s) { final n = double.tryParse(s ?? ''); return n == null || !n.isFinite || n < 0 || n > 366 || n * 2 != (n * 2).roundToDouble() ? 'Enter 0–366 days in half-day increments.' : null; },
      ))),
    ])))),
    actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Close')), FilledButton(onPressed: loading || saving || rows.isEmpty ? null : save, child: Text(saving ? 'Saving…' : 'Save Policies'))],
  );
}
