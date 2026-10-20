import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_storage.dart';

class HrmsAttendanceTimeApi {
  HrmsAttendanceTimeApi._();

  static Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getString('auth_token');
    return {'Content-Type': 'application/json', if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'};
  }

  static Map<String, dynamic> _decode(http.Response response) {
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (decoded is! Map) throw Exception('Unexpected response');
    final map = Map<String, dynamic>.from(decoded);
    if (response.statusCode >= 400 || map['success'] == false) throw Exception(map['message']?.toString() ?? 'Request failed');
    final data = map['data'];
    return data is Map ? Map<String, dynamic>.from(data) : map;
  }

  static Future<Map<String, dynamic>> load() async {
    final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/hrms/dashboard/time-settings'), headers: await _headers());
    return _decode(response);
  }

  static Future<void> save({String? checkIn, String? checkOut, String? lateAfter, String? absentAfter, Map<String, String>? male, Map<String, String>? female, String? labourLunchStart, String? labourLunchEnd, String? employeeLunchStart, String? employeeLunchEnd,}) async {
    final payload = <String, dynamic>{};
    if (male != null || female != null) {
      if (male != null) payload['male'] = male;
      if (female != null) payload['female'] = female;
    } else {
      payload.addAll({'shiftStart': checkIn, 'shiftEnd': checkOut, 'lateAfter': lateAfter, 'absentAfter': absentAfter});
    }
    if (labourLunchStart != null) payload['labourLunchStart'] = labourLunchStart;
    if (labourLunchEnd != null) payload['labourLunchEnd'] = labourLunchEnd;
    if (employeeLunchStart != null) payload['employeeLunchStart'] = employeeLunchStart;
    if (employeeLunchEnd != null) payload['employeeLunchEnd'] = employeeLunchEnd;
    final response = await http.put(Uri.parse('${ApiConfig.baseUrl}/hrms/dashboard/time-settings'), headers: await _headers(), body: jsonEncode(payload));
    _decode(response);
  }
}
