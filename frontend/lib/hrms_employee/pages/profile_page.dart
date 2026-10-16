import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/api_config.dart';
import '../../services/auth_storage.dart';
import '../shared/employee_ui.dart';

class EmployeeProfilePage extends StatefulWidget {
  const EmployeeProfilePage({super.key});
  @override
  State<EmployeeProfilePage> createState() => _EmployeeProfilePageState();
}

class _EmployeeProfilePageState extends State<EmployeeProfilePage> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{
    for (final key in [
      'firstName',
      'middleName',
      'lastName',
      'phone',
      'panNumber',
      'aadhaarNumber',
      'accountHolderName',
      'bankAccountNumber',
      'ifscCode',
      'bankNameBranch',
      'permanentAddress',
      'temporaryAddress',
    ])
      key: TextEditingController(),
  };
  Map<String, dynamic> _work = const {};
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _load() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/auth/profile'),
        headers: await _headers(),
      );
      final body = jsonDecode(response.body);
      if (body is Map && body['success'] == true && body['data'] is Map) {
        final data = Map<String, dynamic>.from(body['data'] as Map);
        for (final entry in _fields.entries) {
          entry.value.text = data[_dbKey(entry.key)]?.toString() ?? '';
        }
        if (_fields['firstName']!.text.isEmpty)
          _fields['firstName']!.text = data['first_name']?.toString() ?? '';
        if (_fields['lastName']!.text.isEmpty)
          _fields['lastName']!.text = data['last_name']?.toString() ?? '';
        _work = data;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _dbKey(String key) =>
      key.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        for (final item in _fields.entries) item.key: item.value.text,
      };
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/auth/profile'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
      final body = jsonDecode(response.body);
      if (response.statusCode >= 400 || body is! Map || body['success'] != true)
        throw Exception(
          body is Map ? body['message'] : 'Could not save profile',
        );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved successfully.')),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _input(
    String key,
    String label, {
    bool required = false,
    int lines = 1,
  }) => TextFormField(
    controller: _fields[key],
    maxLines: lines,
    validator: required
        ? (value) => (value ?? '').trim().isEmpty ? '$label is required' : null
        : null,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
  Widget _section(String title, IconData icon, List<Widget> children) =>
      EmployeeCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: employeeBlue),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: employeeNavy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              runSpacing: 16,
              spacing: 16,
              children: children
                  .map((child) => SizedBox(width: 360, child: child))
                  .toList(),
            ),
          ],
        ),
      );
  @override
  Widget build(BuildContext context) => EmployeeScaffold(
    route: '/employee/profile',
    title: 'Profile Settings',
    subtitle:
        'View and update your personal, contact, bank, and address details.',
    desktop: _body(),
    mobile: _body(),
  );
  Widget _body() {
    if (_loading)
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF102E80), employeeBlue],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.person_rounded, color: Colors.white, size: 34),
                SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profile Management',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Keep your personal and payroll details up to date.',
                      style: TextStyle(color: Color(0xFFDCE8FF)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _section('Personal Information', Icons.person_outline, [
            _input('firstName', 'First name', required: true),
            _input('middleName', 'Middle name'),
            _input('lastName', 'Last name', required: true),
          ]),
          const SizedBox(height: 16),
          _section('Identification & Contact', Icons.badge_outlined, [
            _input('phone', 'Phone number'),
            _input('panNumber', 'PAN card number'),
            _input('aadhaarNumber', 'Aadhaar number'),
          ]),
          const SizedBox(height: 16),
          _section(
            'Bank Details (for payslip)',
            Icons.account_balance_outlined,
            [
              _input('accountHolderName', 'Account holder name'),
              _input('bankAccountNumber', 'Account number'),
              _input('ifscCode', 'IFSC code'),
              _input('bankNameBranch', 'Bank name & branch'),
            ],
          ),
          const SizedBox(height: 16),
          _section('Address Details', Icons.location_on_outlined, [
            _input('permanentAddress', 'Permanent address', lines: 2),
            _input('temporaryAddress', 'Temporary address', lines: 2),
          ]),
          const SizedBox(height: 16),
          _section('Work Information (managed by admin)', Icons.work_outline, [
            Text(
              'Employee ID: ${_work['employee_code'] ?? _work['staff_id'] ?? '—'}',
            ),
            Text('Department: ${_work['department'] ?? '—'}'),
            Text('Role: ${_work['role'] ?? '—'}'),
            Text('Work mode: ${_work['work_mode'] ?? '—'}'),
          ]),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(_saving ? 'Saving...' : 'Save Profile'),
            ),
          ),
        ],
      ),
    );
  }
}
