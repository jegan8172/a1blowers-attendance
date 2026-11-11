import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_storage.dart';

abstract final class HrmsClockLogsApi {
  static Future<Map<String, dynamic>> calendar({
    required int employeeId,
    required DateTime month,
  }) async {
    final token = await AuthStorage.getString('auth_token');
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/attendance/clock-logs/calendar').replace(
        queryParameters: {
          'employeeId': '$employeeId',
          'month': '${month.year}-${month.month.toString().padLeft(2, '0')}',
        },
      ),
      headers: {if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'},
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final result = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (response.statusCode >= 400 || result['success'] == false) {
      throw Exception(result['message']?.toString() ?? 'Could not load attendance calendar');
    }
    return result['data'] is Map ? Map<String, dynamic>.from(result['data']) : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> correctStatus({
    required int employeeId,
    required DateTime date,
    required String status,
    required String reason,
  }) async {
    final token = await AuthStorage.getString('auth_token');
    final response = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/attendance/clock-logs/status'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'employeeId': employeeId,
        'date': _date(date),
        'status': status,
        'reason': reason,
      }),
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final result = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (response.statusCode >= 400 || result['success'] == false) {
      throw Exception(result['message']?.toString() ?? 'Could not save attendance correction');
    }
    return result;
  }

  static Future<Map<String, dynamic>> attendanceDetails({
    required int employeeId,
    required DateTime date,
  }) async {
    final token = await AuthStorage.getString('auth_token');
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/attendance/details').replace(
        queryParameters: {'employeeId': '$employeeId', 'date': _date(date)},
      ),
      headers: {if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'},
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final map = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (response.statusCode >= 400 || map['success'] == false) {
      throw Exception(map['message']?.toString() ?? 'Could not load attendance details');
    }
    return map['data'] is Map ? Map<String, dynamic>.from(map['data']) : <String, dynamic>{};
  }
  static Future<List<Map<String, dynamic>>> remarks(String id) async {
    final token = await AuthStorage.getString('auth_token');
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/attendance/clock-logs/$id/remarks'),
      headers: {if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'},
    );
    final result = jsonDecode(response.body) as Map;
    if (response.statusCode >= 400 || result['success'] == false) {
      throw Exception(result['message'] ?? 'Could not load remarks');
    }
    return (result['data'] as List? ?? []).whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item)).toList();
  }

  static Future<void> addRemark(String id, String remark) async {
    final token = await AuthStorage.getString('auth_token');
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/attendance/clock-logs/$id/remarks'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'remark': remark}),
    );
    final result = jsonDecode(response.body) as Map;
    if (response.statusCode >= 400 || result['success'] == false) {
      throw Exception(result['message'] ?? 'Could not save remark');
    }
  }
  static Future<Map<String, dynamic>> list({
    required DateTime date,
    required bool monthly,
    int? employeeId,
  }) async {
    final query = <String, String>{
      'view': monthly ? 'month' : 'day',
      'date': _date(date),
      'month': '${date.year}-${date.month.toString().padLeft(2, '0')}',
      if (employeeId != null) 'employeeId': '$employeeId',
    };
    final token = await AuthStorage.getString('auth_token');
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/attendance/clock-logs')
          .replace(queryParameters: query),
      headers: {if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'},
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final map = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (response.statusCode >= 400 || map['success'] == false) {
      throw Exception(map['message']?.toString() ?? 'Could not load clock logs');
    }
    return map['data'] is Map ? Map<String, dynamic>.from(map['data']) : map;
  }

  static Future<List<Map<String, dynamic>>> overtimeHistory(int employeeId) async {
    final token = await AuthStorage.getString('auth_token');
    final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/attendance/overtime/$employeeId/history'), headers: {if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'});
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final map = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (response.statusCode >= 400 || map['success'] == false) throw Exception(map['message']?.toString() ?? 'Could not load overtime history');
    final data = map['data'];
    return data is List ? data.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : const [];
  }

  static String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
