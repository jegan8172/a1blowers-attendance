import 'package:flutter/foundation.dart';

/// Temporary in-app state for the employee UI. It will be connected to the
/// attendance API when the backend integration phase begins.
class EmployeeSession extends ChangeNotifier {
  EmployeeSession._();

  static final EmployeeSession instance = EmployeeSession._();

  bool _checkedIn = true;
  DateTime? _clockInAt = DateTime(2026, 8, 23, 9, 22);

  bool get checkedIn => _checkedIn;
  DateTime? get clockInAt => _clockInAt;

  void clockIn() {
    _checkedIn = true;
    _clockInAt = DateTime.now();
    notifyListeners();
  }

  void clockOut() {
    _checkedIn = false;
    notifyListeners();
  }
}
