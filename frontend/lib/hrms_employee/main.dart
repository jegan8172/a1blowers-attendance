import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

import 'pages/attendance_page.dart';
import 'pages/clock_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/extra_hours_page.dart';
import 'pages/leave_page.dart';
import 'pages/permission_page.dart';
import 'pages/salary_page.dart';
import 'pages/tracking_page.dart';

void main() => runApp(
  ChangeNotifierProvider(
    create: (_) => AuthService(),
    child: const EmployeePortal(),
  ),
);

class EmployeePortal extends StatelessWidget {
  const EmployeePortal({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Go Digital Employee Portal',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF5F8FD),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1769E0),
        primary: const Color(0xFF1769E0),
        surface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF07143F),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1769E0),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFD9E4F4)),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFF1769E0), width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      textTheme: GoogleFonts.manropeTextTheme(
        const TextTheme(
          headlineLarge: TextStyle(
            color: Color(0xFF07143F),
            fontWeight: FontWeight.w800,
          ),
          titleLarge: TextStyle(
            color: Color(0xFF07143F),
            fontWeight: FontWeight.w700,
          ),
          bodyMedium: TextStyle(color: Color(0xFF263451)),
        ),
      ),
    ),
    // EmployeePortal is opened by the parent app only after the user has
    // authenticated.  Start at the dashboard instead of creating a
    // second login flow inside the Attendance workspace.
    initialRoute: '/employee/dashboard',
    routes: {
      '/': (_) => const EmployeeDashboardPage(),
      '/attendance': (_) => const EmployeeDashboardPage(),
      '/employee/dashboard': (_) => const EmployeeDashboardPage(),
      '/employee/attendance': (_) => const EmployeeAttendancePage(),
      '/employee/clock-log': (_) => const EmployeeClockPage(),
      '/employee/leave': (_) => const EmployeeLeavePage(),
      '/employee/permission': (_) => const EmployeePermissionPage(),
      '/employee/extra-hours': (_) => const EmployeeExtraHoursPage(),
      '/employee/salary': (_) => const EmployeeSalaryPage(),
      '/employee/tracking': (_) => const EmployeeTrackingPage(),
    },
  );
}
