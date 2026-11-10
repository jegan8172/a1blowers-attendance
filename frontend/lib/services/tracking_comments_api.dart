import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class TrackingCommentsApi {
  static Future<List<Map<String, dynamic>>> myComments(String token) async {
    final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/comments'), headers: {'Authorization': 'Bearer $token'});
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) throw Exception(body['message'] ?? 'Unable to load comments');
    return ((body['data']?['items'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<List<Map<String, dynamic>>> myPopupComments(String token) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/my-field-waiting-reasons'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(body['message'] ?? 'Unable to load popup comments');
    }
    return ((body['data']?['items'] as List?) ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<void> addComment(String token, String comment, {double? latitude, double? longitude, String? address}) async {
    final response = await http.post(Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/comments'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'comment': comment, 'latitude': latitude, 'longitude': longitude, 'address': address}));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) throw Exception(body['message'] ?? 'Unable to save comment');
  }

  static Future<List<Map<String, dynamic>>> adminComments(String token) async {
    final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/admin-comments'), headers: {'Authorization': 'Bearer $token'});
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) throw Exception(body['message'] ?? 'Unable to load employee comments');
    return ((body['data']?['items'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
