import 'package:flutter/material.dart';
import '../../core/employee_shell.dart';
import '../../core/employee_nav.dart';

/// See HRMS_PROJECT_BLUEPRINT.md, Section 1 for this page's purpose.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  static Widget builder(BuildContext context) => const DashboardPage();

  @override
  Widget build(BuildContext context) {
    return EmployeeShell(
      current: EmployeeNavItem.dashboard,
      body:
          const Center(child: Text('DashboardPage — pending design reference')),
    );
  }
}
