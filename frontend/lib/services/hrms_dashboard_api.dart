import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_storage.dart';

class HrmsDashboardApi {
  HrmsDashboardApi._();

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

  static Future<Map<String, dynamic>> month({
    required int year,
    required int month,
    int weeklyOff = 7,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/hrms/dashboard').replace(
      queryParameters: {
        'year': '$year',
        'month': '$month',
        'weeklyOff': '$weeklyOff',
      },
    );
    final response = await http.get(uri, headers: await _headers());
    return _decode(response);
  }

  static Future<List<Map<String, dynamic>>> calendarOverrides() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/dashboard/calendar-overrides'),
      headers: await _headers(),
    );
    final data = _decode(response);
    return (data['overrides'] as List? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<void> saveCalendarOverride(Map<String, dynamic> override) async {
    final response = await http.put(
      Uri.parse('${ApiConfig.baseUrl}/hrms/dashboard/calendar-overrides'),
      headers: await _headers(),
      body: jsonEncode(override),
    );
    _decode(response);
  }
}
