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
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF101B35),
          contentTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          actionTextColor: Color(0xFF93C5FD),
          closeIconColor: Colors.white,
          elevation: 18,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          insetPadding: EdgeInsets.fromLTRB(16, 0, 16, 20),
        ),
      ),
      initialRoute: '/employee/dashboard',
      routes: AppRouter.routes,
      debugShowCheckedModeBanner: false,
    );
  }
}
