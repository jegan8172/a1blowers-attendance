import 'package:flutter/material.dart';
import 'package:hrms_design_system/hrms_design_system.dart';
import '../routing/app_router.dart';

class EmployeePortalApp extends StatelessWidget {
  const EmployeePortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Go Digital HRMS — Employee',
      theme: HrmsTheme.light(),
      initialRoute: '/employee/dashboard',
      routes: AppRouter.routes,
      debugShowCheckedModeBanner: false,
    );
  }
}
