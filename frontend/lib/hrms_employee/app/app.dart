import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hrms_design_system/hrms_design_system.dart';
import '../routing/app_router.dart';

class EmployeePortalApp extends StatelessWidget {
  const EmployeePortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = HrmsTheme.light();
    return MaterialApp(
      title: 'Go Digital HRMS — Employee',
      theme: baseTheme.copyWith(
        textTheme: GoogleFonts.manropeTextTheme(baseTheme.textTheme),
      ),
      initialRoute: '/employee/dashboard',
      routes: AppRouter.routes,
      debugShowCheckedModeBanner: false,
    );
  }
}
