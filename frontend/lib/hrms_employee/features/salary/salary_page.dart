import 'package:flutter/material.dart';
import '../../core/employee_shell.dart';
import '../../core/employee_nav.dart';

/// See HRMS_PROJECT_BLUEPRINT.md, Section 1 for this page's purpose.
class SalaryPage extends StatelessWidget {
  const SalaryPage({super.key});

  static Widget builder(BuildContext context) => const SalaryPage();

  @override
  Widget build(BuildContext context) {
    return EmployeeShell(
      current: EmployeeNavItem.salary,
      body: const Center(child: Text('SalaryPage — pending design reference')),
    );
  }
}
