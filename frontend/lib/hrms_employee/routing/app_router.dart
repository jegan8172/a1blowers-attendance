import 'package:flutter/material.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/attendance/attendance_page.dart';
import '../features/clock_log/clock_log_page.dart';
import '../features/leave/leave_page.dart';
import '../features/extra_hours/extra_hours_page.dart';
import '../features/salary/salary_page.dart';
import '../features/tracking/tracking_page.dart';

/// Routes per HRMS_PROJECT_BLUEPRINT.md, Section 1 (Approved Employee pages).
class AppRouter {
  AppRouter._();

  static final Map<String, WidgetBuilder> routes = {
    '/employee/dashboard': DashboardPage.builder,
    '/employee/attendance': AttendancePage.builder,
    // '/employee/clock-log': ClockLogPage.builder,
    '/employee/clock-log': ClockLogPage.builder,
    '/employee/leave': LeavePage.builder,
    '/employee/extra-hours': ExtraHoursPage.builder,
    '/employee/salary': SalaryPage.builder,
    '/employee/tracking': TrackingPage.builder,
  };
}
