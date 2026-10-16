import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'auth_storage.dart';
import 'payslip_download.dart';

class HrmsPayslipApi {
  static Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<List<Map<String, dynamic>>> mine() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/payslips/my'),
      headers: await _headers(),
    );
    final body = jsonDecode(response.body);
    if (response.statusCode >= 400 || body['success'] != true)
      throw Exception(body['message'] ?? 'Unable to load payslips');
    final data = body['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Map<String, dynamic>> summary() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/payslips/my/summary'),
      headers: await _headers(),
    );
    final body = jsonDecode(response.body);
    if (response.statusCode >= 400 || body['success'] != true)
      throw Exception(body['message'] ?? 'Unable to load salary');
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : const {};
  }

  static Future<List<Map<String, dynamic>>> deductionHistory() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/payslips/my/deduction-history'),
      headers: await _headers(),
    );
    final body = jsonDecode(response.body);
    if (response.statusCode >= 400 || body['success'] != true)
      throw Exception(body['message'] ?? 'Unable to load deduction history');
    final data = body['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<void> request(int payrollId) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/hrms/payslips/$payrollId/request'),
      headers: await _headers(),
    );
    final body = jsonDecode(response.body);
    if (response.statusCode >= 400 || body['success'] != true)
      throw Exception(body['message'] ?? 'Unable to send request');
  }

  static Future<void> download(int payrollId) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/payslips/$payrollId/download'),
      headers: await _headers(),
    );
    if (response.statusCode >= 400) {
      final body = jsonDecode(response.body);
      throw Exception(body['message'] ?? 'Unable to download payslip');
    }
    final bytes = response.bodyBytes;
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().startsWith('application/pdf') ||
        bytes.length < 5 ||
        ascii.decode(bytes.take(5).toList(), allowInvalid: true) != '%PDF-') {
      throw Exception(
        'The server did not return a PDF. No file was downloaded. Please contact your administrator.',
      );
    }
    await downloadPayslipPdf(bytes, 'Salary-Slip-$payrollId.pdf');
  }
}
