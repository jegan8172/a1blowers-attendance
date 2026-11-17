import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'auth_storage.dart';

class ChatApi {
  ChatApi._();
  static Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getString('auth_token');
    return {'Content-Type': 'application/json', if (token?.isNotEmpty == true) 'Authorization': 'Bearer $token'};
  }
  static Future<dynamic> _request(String method, String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat$path');
    final headers = await _headers();
    final response = switch (method) {
      'GET' => await http.get(uri, headers: headers),
      'PUT' => await http.put(uri, headers: headers, body: jsonEncode(body)),
      'DELETE' => await http.delete(uri, headers: headers, body: jsonEncode(body)),
      _ => await http.post(uri, headers: headers, body: jsonEncode(body)),
    };
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400 || decoded['success'] == false) throw Exception(decoded['message'] ?? 'Chat request failed');
    return decoded['data'];
  }
  static Future<List<Map<String, dynamic>>> conversations() async => List<Map<String, dynamic>>.from(await _request('GET', '/conversations') as List);
  static Future<List<Map<String, dynamic>>> people() async => List<Map<String, dynamic>>.from(await _request('GET', '/people') as List);
  static Future<int> direct(int userId) async => (await _request('POST', '/conversations/direct', body: {'userId': userId}) as Map<String, dynamic>)['id'] as int;
  static Future<int> createGroup(String name, List<int> memberIds) async => (await _request('POST', '/conversations/group', body: {'name': name, 'memberIds': memberIds}) as Map<String, dynamic>)['id'] as int;
  static Future<Map<String, dynamic>> messages(int id) async => Map<String, dynamic>.from(await _request('GET', '/conversations/$id/messages') as Map);
  static Future<List<Map<String, dynamic>>> attachments(int id) async => List<Map<String, dynamic>>.from(await _request('GET', '/conversations/$id/attachments') as List);
  static Future<void> send(int id, String body) async { await _request('POST', '/conversations/$id/messages', body: {'body': body}); }
  static Future<void> read(int id, int messageId) async { await _request('POST', '/conversations/$id/read', body: {'messageId': messageId}); }
  static Future<void> mute(int id, int minutes) async { await _request('PUT', '/conversations/$id/mute', body: {'minutes': minutes}); }
  static Future<List<Map<String, dynamic>>> search(int id, String query) async => List<Map<String, dynamic>>.from(await _request('GET', '/conversations/$id/search?q=${Uri.encodeQueryComponent(query)}') as List);
  static Future<List<Map<String, dynamic>>> pins(int id) async => List<Map<String, dynamic>>.from(await _request('GET', '/conversations/$id/pins') as List);
  static Future<void> pin(int id, int messageId) async { await _request('POST', '/conversations/$id/pins/$messageId'); }
  static Future<void> unpin(int id, int messageId) async { await _request('DELETE', '/conversations/$id/pins/$messageId'); }
  static Future<Map<String, dynamic>> attendanceSummary(int id) async => Map<String, dynamic>.from(await _request('GET', '/conversations/$id/attendance-summary') as Map);
  static Future<Map<String, dynamic>> dial(int id) async => Map<String, dynamic>.from(await _request('GET', '/conversations/$id/dial') as Map);
  static Future<void> delivered(int id, int messageId) async { await _request('POST', '/conversations/$id/delivered', body: {'messageId': messageId}); }
  static Future<void> upload(int id, Uint8List bytes, String name) async {
    final request = http.MultipartRequest('POST', Uri.parse('${ApiConfig.baseUrl}/chat/conversations/$id/attachments'));
    final headers = await _headers();
    headers.remove('Content-Type');
    request.headers.addAll(headers);
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));
    final response = await http.Response.fromStream(await request.send());
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400 || decoded['success'] == false) throw Exception(decoded['message'] ?? 'Upload failed');
  }
}
