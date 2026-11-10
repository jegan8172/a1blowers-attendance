import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_storage.dart';

class HrmsNotificationsApi {
  HrmsNotificationsApi._();

  static Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _decode(http.Response response) {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    if (decoded is! Map) throw Exception('Unexpected response');
    final map = Map<String, dynamic>.from(decoded);
    if (response.statusCode >= 400 || map['success'] == false) {
      throw Exception(map['message']?.toString() ?? 'Request failed');
    }
    return map['data'] is Map
        ? Map<String, dynamic>.from(map['data'] as Map)
        : map;
  }

  static Future<Map<String, dynamic>> list() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/approvals/notifications'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  static Future<void> markAllRead() async {
    final response = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/hrms/approvals/notifications/read-all'),
      headers: await _headers(),
    );
    _decode(response);
  }

  static Future<Map<String, dynamic>> updateSettings(
    Map<String, dynamic> settings,
  ) async {
    final response = await http.put(
      Uri.parse('${ApiConfig.baseUrl}/hrms/approvals/notifications/settings'),
      headers: await _headers(),
      body: jsonEncode(settings),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> uploadCustomSound(
    Uint8List bytes,
    String filename,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        '${ApiConfig.baseUrl}/hrms/approvals/notifications/settings/sound',
      ),
    );
    final headers = await _headers();
    headers.remove('Content-Type');
    request.headers.addAll(headers);
    request.files.add(
      http.MultipartFile.fromBytes('sound', bytes, filename: filename),
    );
    final response = await http.Response.fromStream(await request.send());
    return _decode(response);
  }
}
