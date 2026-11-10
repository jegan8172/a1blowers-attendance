import 'package:flutter/material.dart';
import '../../../services/auth_storage.dart';
import '../../../services/tracking_comments_api.dart';

class AdminTrackingCommentsPanel extends StatefulWidget {
  const AdminTrackingCommentsPanel({super.key});

  @override
  State<AdminTrackingCommentsPanel> createState() => _AdminTrackingCommentsPanelState();
}

class _AdminTrackingCommentsPanelState extends State<AdminTrackingCommentsPanel> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> items = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final token = await AuthStorage.getString('auth_token');
      if (token == null || token.isEmpty) throw Exception('Login required');
      final result = await TrackingCommentsApi.adminComments(token);
      if (mounted) setState(() { items = result; loading = false; });
    } catch (e) {
      if (mounted) setState(() { error = e.toString().replaceFirst('Exception: ', ''); loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Employee Comments', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh)),
          ]),
          const Text('Field and Hybrid employee comments from the last 30 days.'),
          const SizedBox(height: 10),
          if (loading) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
          if (!loading && error != null) Text(error!, style: const TextStyle(color: Colors.red)),
          if (!loading && error == null && items.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No employee comments yet.')),
          ..._grouped().entries.map((entry) => ExpansionTile(
            title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${entry.value.length} comment(s)'),
            children: entry.value.map((item) => ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text('${item['comment'] ?? ''}'),
              subtitle: Text('${item['createdAt'] ?? ''}\n${item['address'] ?? 'Location not recorded'}'),
            )).toList(),
          )),
        ]),
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _grouped() {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final name = '${item['fullName'] ?? item['employeeName'] ?? item['employee_code'] ?? 'Employee'}';
      result.putIfAbsent(name, () => []).add(item);
    }
    return result;
  }
}
