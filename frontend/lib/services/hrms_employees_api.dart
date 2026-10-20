import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_storage.dart';

class HrmsEmployeesApi {
  HrmsEmployeesApi._();

  static Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> createRole(String role) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/hrms/roles'),
      headers: await _headers(),
      body: jsonEncode({'role': role}),
    );
    return _decode(response);
  }

  static Map<String, dynamic> _decode(http.Response response) {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
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
    String search = '',
    String department = 'All Departments',
    String status = 'All Status',
    String workMode = 'All Work Modes',
    int page = 1,
    int limit = 6,
  }) async {
    final query = {
      'search': search,
      'department': department,
      'status': status,
      'workMode': workMode,
      'page': '$page',
      'limit': '$limit',
    };
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/hrms/employees',
    ).replace(queryParameters: query);
    final response = await http.get(uri, headers: await _headers());
    return _decode(response);
  }

  static Future<Map<String, dynamic>> create(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/hrms/employees'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> detail(int id) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/employees/$id'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> update(
    int id,
    Map<String, dynamic> body,
  ) async {
    final response = await http.put(
      Uri.parse('${ApiConfig.baseUrl}/hrms/employees/$id'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> updateStatus(
    int id,
    String status,
  ) async {
    final response = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/hrms/employees/$id/status'),
      headers: await _headers(),
      body: jsonEncode({'status': status}),
    );
    return _decode(response);
  }

  static Future<void> delete(int id) async {
    final response = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}/hrms/employees/$id'),
      headers: await _headers(),
    );
    _decode(response);
  }

  static Future<Map<String, dynamic>> resetPassword(
    int id,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/hrms/employees/$id/password-reset'),
      headers: await _headers(),
      body: jsonEncode({'password': password}),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> deviceRequests() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/employees/device-requests'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> reviewDeviceRequest(
    int id,
    bool approved, {
    String note = '',
  }) async {
    final response = await http.post(
      Uri.parse(
        '${ApiConfig.baseUrl}/hrms/employees/device-requests/$id/review',
      ),
      headers: await _headers(),
      body: jsonEncode({'approved': approved, 'note': note}),
    );
    return _decode(response);
  }

  static Future<String> exportCsv() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/employees/export'),
      headers: await _headers(),
    );
    if (response.statusCode >= 400) {
      throw Exception('Export failed');
    }
    return response.body;
  }
}
