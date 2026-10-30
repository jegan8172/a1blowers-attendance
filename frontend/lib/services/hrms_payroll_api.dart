import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_storage.dart';

class HrmsPayrollApi {
  HrmsPayrollApi._();

  static Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _decode(http.Response response) {
    final decoded =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Unexpected response');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (response.statusCode >= 400 || map['success'] == false) {
      throw Exception(map['message']?.toString() ?? 'Request failed');
    }
    final data = map['data'];
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return map;
  }

  static Future<Map<String, dynamic>> list({
    required int year,
    required int month,
    String employee = 'All Employees',
    String status = 'All Status',
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/hrms/payroll').replace(
      queryParameters: {
        'year': '$year',
        'month': '$month',
        'employee': employee,
        'status': status,
      },
    );
    final response = await http.get(uri, headers: await _headers());
    return _decode(response);
  }

  static Future<Map<String, dynamic>> generate({
    required int year,
    required int month,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/hrms/payroll/generate'),
      headers: await _headers(),
      body: jsonEncode({'year': year, 'month': month}),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> policy() async {
    final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/hrms/payroll/policy'), headers: await _headers());
    return _decode(response);
  }

  static Future<Map<String, dynamic>> savePolicy(Map<String, dynamic> policy) async {
    final response = await http.put(Uri.parse('${ApiConfig.baseUrl}/hrms/payroll/policy'), headers: await _headers(), body: jsonEncode(policy));
    return _decode(response);
  }

  static Future<Map<String, dynamic>> markPaid(int id) async {
    final response = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/hrms/payroll/$id'),
      headers: await _headers(),
      body: jsonEncode({'status': 'paid'}),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> revertPaid(int id, String reason) async {
    final response = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/hrms/payroll/$id'),
      headers: await _headers(),
      body: jsonEncode({'status': 'pending', 'reason': reason}),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> deductionHistory({required int profileId, required int year, required int month}) async {
    final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/hrms/payroll/$profileId/deduction-history?year=$year&month=$month'), headers: await _headers());
    final data = _decode(response);
    final rawItems = data['items'];
    final List items = rawItems is List ? rawItems : const [];
    return {
      'summary': data['summary'] is Map ? Map<String, dynamic>.from(data['summary']) : null,
      'items': items.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList(),
    };
  }

  static Future<List<Map<String, dynamic>>> payrollHistory({required int profileId}) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/payroll/$profileId/history'),
      headers: await _headers(),
    );
    final data = _decode(response);
    final raw = data['data'];
    final rawItems = raw is List ? raw : (data['items'] is List ? data['items'] : const []);
    final result = <Map<String, dynamic>>[];
    for (final item in rawItems) {
      if (item is Map) result.add(Map<String, dynamic>.from(item));
    }
    return result;
  }

  static Future<Map<String, dynamic>> saveCycleOverride({
    required int profileId,
    required int year,
    required int month,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    String ymd(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    final response = await http.put(
      Uri.parse('${ApiConfig.baseUrl}/hrms/payroll/$profileId/cycle-override'),
      headers: await _headers(),
      body: jsonEncode({
        'year': year,
        'month': month,
        'periodStart': ymd(periodStart),
        'periodEnd': ymd(periodEnd),
      }),
    );
    return _decode(response);
  }
}
