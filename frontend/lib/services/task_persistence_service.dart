// ═══════════════════════════════════════════════════════════════════════════════════
// AUTO-SAVE SERVICE - Handles all data persistence with employee tracking
// Add this as a new file: lib/services/task_persistence_service.dart
// ═══════════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';


class TaskPersistenceService {
  // static const String _baseUrl = '/api';
  static String get _baseUrl => ApiConfig.baseUrl;
  
  // Debounce timers for each field
  static final Map<String, Timer> _debounceTimers = {};
  
  // Queue for pending saves
  static final List<Map<String, dynamic>> _savingQueue = [];
  static bool _isSaving = false;

  /// ✅ AUTO-SAVE WITH EMPLOYEE ID & NAME
  static Future<void> autoSaveTaskData({
    required String taskKey,
    required String employeeName,
    required String employeeId,
    required String clientName,
    required String taskName,
    required int rowIndex,
    required Map<String, dynamic> data,
    String? fieldName,
  }) async {
    try {
      debugPrint('💾 Auto-saving: $fieldName for $taskKey');

      // Debounce rapid changes
      _debounceTimers[taskKey]?.cancel();
      _debounceTimers[taskKey] = Timer(const Duration(milliseconds: 500), () async {
        await _sendToBackend({
          'taskKey': taskKey,
          'employeeName': employeeName,
          'employeeId': employeeId,
          'clientName': clientName,
          'taskName': taskName,
          'rowIndex': rowIndex,
          'fieldName': fieldName,
          'data': data,
          'timestamp': DateTime.now().toIso8601String(),
        });
      });
    } catch (e) {
      debugPrint('❌ Auto-save error: $e');
    }
  }

  /// ✅ SAVE ROW COUNT IMMEDIATELY
  static Future<void> saveRowCount({
    required String taskId,
    required String employeeName,
    required String employeeId,
    required String clientName,
    required String taskName,
    required int rowCount,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/task-row-counts/save'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'taskId': taskId,
          'employeeName': employeeName,
          'employeeId': employeeId,
          'clientName': clientName,
          'taskName': taskName,
          'rowCount': rowCount,
          'savedAt': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Row count auto-saved: $rowCount');
      } else {
        debugPrint('⚠️ Row count save failed: ${response.statusCode}');
        _addToQueue({
          'taskId': taskId,
          'employeeName': employeeName,
          'employeeId': employeeId,
          'endpoint': '/task-row-counts/save',
        });
      }
    } catch (e) {
      debugPrint('❌ Error saving row count: $e');
      _addToQueue({
        'taskId': taskId,
        'employeeName': employeeName,
        'employeeId': employeeId,
        'endpoint': '/task-row-counts/save',
      });
    }
  }

  /// ✅ SAVE SUBMIT DATE IMMEDIATELY
  static Future<void> saveSubmitDate({
    required String taskKey,
    required String employeeName,
    required String employeeId,
    required String clientName,
    required String taskName,
    required int rowIndex,
    required String submitDate,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/task-submissions/save'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'taskKey': taskKey,
          'employeeName': employeeName,
          'employeeId': employeeId,
          'clientName': clientName,
          'taskName': taskName,
          'rowIndex': rowIndex,
          'submitDate': submitDate,
          'savedAt': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Submit date auto-saved: $submitDate');
      } else {
        _addToQueue({
          'taskKey': taskKey,
          'endpoint': '/task-submissions/save',
        });
      }
    } catch (e) {
      debugPrint('❌ Error saving submit date: $e');
      _addToQueue({
        'taskKey': taskKey,
        'endpoint': '/task-submissions/save',
      });
    }
  }

  /// ✅ SAVE TASK DESCRIPTION IMMEDIATELY
  static Future<void> saveTaskDescription({
    required String taskKey,
    required String employeeName,
    required String employeeId,
    required String clientName,
    required String taskName,
    required int rowIndex,
    required String taskDescription,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/task-submissions/save'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'taskKey': taskKey,
          'employeeName': employeeName,
          'employeeId': employeeId,
          'clientName': clientName,
          'taskName': taskName,
          'rowIndex': rowIndex,
          'taskDescription': taskDescription,
          'savedAt': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Task description auto-saved');
      } else {
        _addToQueue({
          'taskKey': taskKey,
          'endpoint': '/task-submissions/save',
        });
      }
    } catch (e) {
      debugPrint('❌ Error saving task description: $e');
      _addToQueue({
        'taskKey': taskKey,
        'endpoint': '/task-submissions/save',
      });
    }
  }

  /// ✅ SAVE COMMENT IMMEDIATELY
  static Future<void> saveComment({
    required String taskKey,
    required String employeeName,
    required String employeeId,
    required String clientName,
    required String taskName,
    required int rowIndex,
    required String comment,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/task-comments/save'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'taskKey': taskKey,
          'employeeName': employeeName,
          'employeeId': employeeId,
          'clientName': clientName,
          'taskName': taskName,
          'rowIndex': rowIndex,
          'comment': comment,
          'savedAt': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Comment auto-saved');
      } else {
        _addToQueue({
          'taskKey': taskKey,
          'endpoint': '/task-comments/save',
        });
      }
    } catch (e) {
      debugPrint('❌ Error saving comment: $e');
      _addToQueue({
        'taskKey': taskKey,
        'endpoint': '/task-comments/save',
      });
    }
  }

  /// ✅ SAVE TIME TRACKING EVENT
  static Future<void> saveTimeEvent({
    required String taskKey,
    required String employeeName,
    required String employeeId,
    required String clientName,
    required String taskName,
    required int rowIndex,
    required String eventType, // start, hold, restart, complete, reject
    required Map<String, dynamic> eventData,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/task-time-tracking/$eventType'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'taskKey': taskKey,
          'employeeName': employeeName,
          'employeeId': employeeId,
          'clientName': clientName,
          'taskName': taskName,
          'rowIndex': rowIndex,
          'eventType': eventType,
          ...eventData,
          'savedAt': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Time event saved: $eventType');
      } else {
        _addToQueue({
          'taskKey': taskKey,
          'eventType': eventType,
          'endpoint': '/task-time-tracking/$eventType',
        });
      }
    } catch (e) {
      debugPrint('❌ Error saving time event: $e');
      _addToQueue({
        'taskKey': taskKey,
        'eventType': eventType,
        'endpoint': '/task-time-tracking/$eventType',
      });
    }
  }

  /// ✅ SAVE COMPLETE SNAPSHOT
  static Future<void> saveSnapshot({
    required String taskKey,
    required String employeeName,
    required String employeeId,
    required String clientName,
    required String taskName,
    required int rowIndex,
    required Map<String, dynamic> snapshotData,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/task-time-tracking/complete-snapshot'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'taskKey': taskKey,
          'employeeName': employeeName,
          'employeeId': employeeId,
          'clientName': clientName,
          'taskName': taskName,
          'rowIndex': rowIndex,
          ...snapshotData,
          'savedAt': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Snapshot saved');
      } else {
        _addToQueue({
          'taskKey': taskKey,
          'endpoint': '/task-time-tracking/complete-snapshot',
        });
      }
    } catch (e) {
      debugPrint('❌ Error saving snapshot: $e');
      _addToQueue({
        'taskKey': taskKey,
        'endpoint': '/task-time-tracking/complete-snapshot',
      });
    }
  }

  /// ✅ RETRY FAILED SAVES
  static Future<void> retryFailedSaves() async {
    if (_isSaving || _savingQueue.isEmpty) return;

    _isSaving = true;
    debugPrint('🔄 Retrying ${_savingQueue.length} failed saves...');

    while (_savingQueue.isNotEmpty) {
      final item = _savingQueue.removeAt(0);
      await Future.delayed(const Duration(milliseconds: 200));

      try {
        await http.post(
          Uri.parse('$_baseUrl${item['endpoint']}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(item),
        );
        debugPrint('✅ Retry successful for: ${item['taskKey']}');
      } catch (e) {
        debugPrint('❌ Retry failed: $e');
        _savingQueue.add(item); // Re-add to queue
        break;
      }
    }

    _isSaving = false;
  }

  static void _addToQueue(Map<String, dynamic> item) {
    _savingQueue.add(item);
    debugPrint('⏳ Added to retry queue (${_savingQueue.length} pending)');
  }

  static int getPendingCount() => _savingQueue.length;

  static Future<void> _sendToBackend(Map<String, dynamic> data) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/task-data/save'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      debugPrint('✅ Data auto-saved to backend');
    } catch (e) {
      debugPrint('❌ Backend save failed: $e');
      _addToQueue(data);
    }
  }
}