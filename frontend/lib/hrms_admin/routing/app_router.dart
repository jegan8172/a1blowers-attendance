import 'package:flutter/material.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/clock_logs/clock_logs_page.dart';
import '../features/employees/employees_page.dart';
import '../features/approvals/approvals_page.dart';
import '../features/payroll/payroll_page.dart';
import '../features/tracking/tracking_page.dart';
import '../features/settings/settings_page.dart';
import '../features/settings/weekly_off_templates_page.dart';

/// Routes per HRMS_PROJECT_BLUEPRINT.md, Section 1 (Approved Admin pages).
/// One "Approvals" route covers Leave + Extra Hours; there is no separate
/// Admin Attendance route (Manage Calendar is a Dashboard modal).
class AppRouter {
  AppRouter._();

  static final Map<String, WidgetBuilder> routes = {
    '/admin/dashboard': DashboardPage.builder,
    '/admin/clock-logs': ClockLogsPage.builder,
    '/admin/employees': EmployeesPage.builder,
    '/admin/approvals': ApprovalsPage.builder,
    '/admin/payroll': PayrollPage.builder,
    '/admin/tracking': TrackingPage.builder,
    '/admin/settings': SettingsPage.builder,
    '/admin/weekly-off-templates': WeeklyOffTemplatesPage.builder,
  };
}
