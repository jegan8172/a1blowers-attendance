import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_storage.dart';

class HrmsWeeklyOffTemplatesApi {
  HrmsWeeklyOffTemplatesApi._();

  static Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getString('auth_token');
    return {'Content-Type': 'application/json', if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'};
  }

  static Map<String, dynamic> _decode(http.Response response) {
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (decoded is! Map) throw Exception('Unexpected response');
    final map = Map<String, dynamic>.from(decoded);
    if (response.statusCode >= 400 || map['success'] == false) throw Exception(map['message']?.toString() ?? 'Request failed');
    return map['data'] is Map ? Map<String, dynamic>.from(map['data'] as Map) : map;
  }

  static Future<Map<String, dynamic>> list() async => _decode(await http.get(
    Uri.parse('${ApiConfig.baseUrl}/hrms/weekly-off-templates'), headers: await _headers()));

  static Future<void> create({required String name, required List<int> weeklyOffDays}) async {
    await _decode(await http.post(Uri.parse('${ApiConfig.baseUrl}/hrms/weekly-off-templates'), headers: await _headers(), body: jsonEncode({'name': name, 'weeklyOffDays': weeklyOffDays})));
  }

  static Future<void> update({required int id, required String name, required List<int> weeklyOffDays, required bool active}) async {
    await _decode(await http.put(Uri.parse('${ApiConfig.baseUrl}/hrms/weekly-off-templates/$id'), headers: await _headers(), body: jsonEncode({'name': name, 'weeklyOffDays': weeklyOffDays, 'active': active})));
  }

  static Future<void> assign({required int profileId, required int templateId, required DateTime effectiveFrom}) async {
    final date = '${effectiveFrom.year.toString().padLeft(4, '0')}-${effectiveFrom.month.toString().padLeft(2, '0')}-${effectiveFrom.day.toString().padLeft(2, '0')}';
    await _decode(await http.post(Uri.parse('${ApiConfig.baseUrl}/hrms/weekly-off-templates/assignments'), headers: await _headers(), body: jsonEncode({'profileId': profileId, 'templateId': templateId, 'effectiveFrom': date})));
  }
}
