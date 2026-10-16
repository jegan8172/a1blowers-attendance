import 'package:flutter/material.dart';
import '../../core/employee_shell.dart';
import '../../core/employee_nav.dart';

/// See HRMS_PROJECT_BLUEPRINT.md, Section 1 for this page's purpose.
class ExtraHoursPage extends StatelessWidget {
  const ExtraHoursPage({super.key});

  static Widget builder(BuildContext context) => const ExtraHoursPage();

  @override
  Widget build(BuildContext context) {
    return EmployeeShell(
      current: EmployeeNavItem.extraHours,
      body: const Center(
          child: Text('ExtraHoursPage — pending design reference')),
    );
  }
}
