import 'package:flutter/material.dart';
import '../../core/employee_shell.dart';
import '../../core/employee_nav.dart';

/// See HRMS_PROJECT_BLUEPRINT.md, Section 1 for this page's purpose.
class LeavePage extends StatelessWidget {
  const LeavePage({super.key});

  static Widget builder(BuildContext context) => const LeavePage();

  @override
  Widget build(BuildContext context) {
    return EmployeeShell(
      current: EmployeeNavItem.leave,
      body: const Center(child: Text('LeavePage — pending design reference')),
    );
  }
}
