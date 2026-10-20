// lib/services/task_planner_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';


class TaskPlannerService {
  // static const String _base = '/api/task-planner';
  static String get _base => '${ApiConfig.baseUrl}/task-planner';

  // GET /api/task-planner?employee=NAME
  static Future<List<Map<String, dynamic>>> getPlannerRows(String employeeName) async {
    final r = await http.get(Uri.parse('$_base?employee=$employeeName'));
    if (r.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(r.body)['data'] ?? []);
    }
    throw Exception('Failed to load rows: ${r.statusCode}');
  }

  // GET /api/task-planner/shares?employee=NAME
  static Future<List<Map<String, dynamic>>> getShareHistory(String employeeName) async {
    final r = await http.get(Uri.parse('$_base/shares?employee=$employeeName'));
    if (r.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(r.body)['data'] ?? []);
    }
    throw Exception('Failed to load share history: ${r.statusCode}');
  }

  // POST /api/task-planner
  static Future<int> createPlannerRow(String employeeName, String contentType) async {
    final r = await http.post(
      Uri.parse(_base),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'employeeName': employeeName,
        'contentType':  contentType,
        'content':      '',
      }),
    );
    if (r.statusCode == 201) {
      return jsonDecode(r.body)['data']['id'] as int;
    }
    throw Exception('Failed to create row: ${r.statusCode}');
  }

  // PUT /api/task-planner/:id
  static Future<void> updatePlannerRow({
  required int id,
  required String contentType,
  required String content,
}) async {
  final r = await http.put(
    Uri.parse('$_base/$id'),
    headers: {
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'contentType': contentType,
      'content': content,
    }),
  );

  if (r.statusCode != 200) {
    throw Exception('Failed to update row');
  }
}

  // PATCH /api/task-planner/:id/share
  // Every call = 1 new INSERT into task_planner_shares, never an update
  // Sends sender details (logged-in employee) + receiver details (selected employee)
  static Future<void> sharePlannerRow({
    required int    id,
    // Sender — the logged-in employee who is sharing
    required String senderEmployeeName,
    required int?   senderEmployeeId,
    // Content being shared
    required String contentType,
    required String content,
    // Receiver — the employee being shared to
    required String receiverEmployeeName,
    required int?   receiverEmployeeId,
    required String receiverRole,
    required String receiverShort,
  }) async {
    final r = await http.patch(
      Uri.parse('$_base/$id/share'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'senderEmployeeName':   senderEmployeeName,
        'senderEmployeeId':     senderEmployeeId,
        'contentType':          contentType,
        'content':              content,
        'receiverEmployeeName': receiverEmployeeName,
        'receiverEmployeeId':   receiverEmployeeId,
        'receiverRole':         receiverRole,
        'receiverShort':        receiverShort,
      }),
    );
    if (r.statusCode != 200) throw Exception('Failed to share: ${r.statusCode}');
  }

  // PATCH /api/task-planner/:id/reset
  static Future<void> resetPlannerRow(int id) async {
    final r = await http.patch(Uri.parse('$_base/$id/reset'));
    if (r.statusCode != 200) throw Exception('Failed to reset: ${r.statusCode}');
  }

  // DELETE /api/task-planner/:id
  static Future<void> deletePlannerRow(int id) async {
    final r = await http.delete(Uri.parse('$_base/$id'));
    if (r.statusCode != 200) throw Exception('Failed to delete: ${r.statusCode}');
  }

  
}