import 'package:flutter/material.dart';
import '../../core/employee_shell.dart';
import '../../core/employee_nav.dart';

/// See HRMS_PROJECT_BLUEPRINT.md, Section 1 for this page's purpose.
class TrackingPage extends StatelessWidget {
  const TrackingPage({super.key});

  static Widget builder(BuildContext context) => const TrackingPage();

  @override
  Widget build(BuildContext context) {
    return EmployeeShell(
      current: EmployeeNavItem.tracking,
      body:
          const Center(child: Text('TrackingPage — pending design reference')),
    );
  }
}
