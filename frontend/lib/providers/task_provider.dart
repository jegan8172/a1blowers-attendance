import 'package:flutter/material.dart';

// ── Task Model ──────────────────────────────────────────────────────────────
class Task {
  final String id;
  final String title;
  final String description;
  final String status; // Pending, In Progress, Completed
  final String priority; // High, Medium, Low
  final String assignedTo;
  final DateTime dueDate;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.assignedTo,
    required this.dueDate,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Untitled',
      description: json['description'] ?? '',
      status: json['status'] ?? 'Pending',
      priority: json['priority'] ?? 'Medium',
      assignedTo: json['assignedTo'] ?? 'Unknown',
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'status': status,
      'priority': priority,
      'assignedTo': assignedTo,
      'dueDate': dueDate.toIso8601String(),
    };
  }
}

// ── Task Provider ───────────────────────────────────────────────────────────
class TaskProvider extends ChangeNotifier {
  List<Task> _tasks = [];
  bool _isLoading = false;
  String? _error;

  List<Task> get tasks => _tasks;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Set tasks loaded from API
  void setTasks(List<Task> tasks) {
    debugPrint('📊 TaskProvider: Setting ${tasks.length} tasks');
    _tasks = tasks;
    _error = null;
    notifyListeners();
  }

  /// Load tasks from API
  Future<void> loadTasks(String token) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // This will be called from LoginScreen's after login function
      debugPrint('📥 TaskProvider: Loading tasks...');
      
      // Your API call will happen in LoginScreen
      // This is just a placeholder
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      debugPrint('❌ TaskProvider error: $e');
    }
  }

  /// Add a new task
  void addTask(Task task) {
    _tasks.add(task);
    notifyListeners();
  }

  /// Update existing task
  void updateTask(Task task) {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _tasks[index] = task;
      notifyListeners();
    }
  }

  /// Delete task
  void deleteTask(String taskId) {
    _tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
  }

  /// Clear all tasks
  void clearTasks() {
    _tasks = [];
    notifyListeners();
  }

  /// Get task by ID
  Task? getTaskById(String id) {
    try {
      return _tasks.firstWhere((t) => t.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get tasks by status
  List<Task> getTasksByStatus(String status) {
    return _tasks.where((t) => t.status.toLowerCase() == status.toLowerCase()).toList();
  }

  /// Get task count by status
  int getTaskCountByStatus(String status) {
    return _tasks
        .where((t) => t.status.toLowerCase() == status.toLowerCase())
        .length;
  }
}