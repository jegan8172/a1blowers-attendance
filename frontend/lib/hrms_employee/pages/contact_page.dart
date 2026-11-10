import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/api_config.dart';
import '../../services/auth_storage.dart';
import '../shared/employee_ui.dart';

class EmployeeContactPage extends StatefulWidget {
  const EmployeeContactPage({super.key});

  @override
  State<EmployeeContactPage> createState() => _EmployeeContactPageState();
}

class _EmployeeContactPageState extends State<EmployeeContactPage> {
  final _phone = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getString('auth_token');
    return {'Content-Type': 'application/json', if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'};
  }

  Future<void> _load() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/auth/contact'), headers: await _headers());
      final data = jsonDecode(response.body);
      if (response.statusCode >= 400 || data is! Map || data['success'] != true || data['data'] is! Map) {
        throw Exception('Unable to load your phone number.');
      }
      if (!mounted) return;
      _phone.text = (data['data'] as Map)['phone']?.toString() ?? '';
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Unable to load your phone number. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final phone = _phone.text.trim();
    if (phone.length > 32 || (phone.isNotEmpty && (!RegExp(r'^[0-9+(). -]+$').hasMatch(phone) || !RegExp(r'[0-9]').hasMatch(phone)))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid phone number using up to 32 characters.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final response = await http.put(Uri.parse('${ApiConfig.baseUrl}/auth/contact'), headers: await _headers(), body: jsonEncode({'phone': phone}));
      final data = jsonDecode(response.body);
      if (response.statusCode >= 400 || data is! Map || data['success'] != true) {
        throw Exception(data is Map ? data['message'] : 'Unable to save phone number.');
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone number saved.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _body() => Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: EmployeeCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Personal information', style: TextStyle(color: employeeNavy, fontWeight: FontWeight.w800, fontSize: 19)),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_loadError != null) ...[
          Text(_loadError!),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ] else ...[
          TextField(controller: _phone, keyboardType: TextInputType.phone, maxLength: 32, enabled: !_saving, decoration: const InputDecoration(labelText: 'Phone number', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save phone number')),
        ],
      ])),
    ),
  );

  @override
  Widget build(BuildContext context) => EmployeeScaffold(route: '/employee/profile', title: 'Profile settings', subtitle: 'Manage your contact information.', desktop: _body(), mobile: _body());
}
