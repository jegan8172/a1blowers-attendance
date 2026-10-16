import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:godigital_portal/services/auth_service.dart';
import 'package:godigital_portal/screens/login_screen.dart';
import 'package:godigital_portal/hrms_admin/app/app.dart' as hrms_admin;
import 'package:godigital_portal/hrms_employee/pages/dashboard_page.dart';
import 'package:godigital_portal/hrms_employee/pages/attendance_page.dart';
import 'package:godigital_portal/hrms_employee/pages/clock_page.dart';
import 'package:godigital_portal/hrms_employee/pages/leave_page.dart';
import 'package:godigital_portal/hrms_employee/pages/permission_page.dart';
import 'package:godigital_portal/hrms_employee/pages/extra_hours_page.dart';
import 'package:godigital_portal/hrms_employee/pages/salary_page.dart';
import 'package:godigital_portal/hrms_employee/pages/tracking_page.dart';
import 'package:godigital_portal/hrms_employee/pages/profile_page.dart';
import 'package:godigital_portal/hrms_employee/shared/field_waiting_prompt_host.dart';
import 'package:godigital_portal/hrms_employee/shared/live_tracking_coordinator.dart';
import 'package:godigital_portal/hrms_employee/shared/android_live_tracking_service.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await AndroidLiveTrackingService.configure();
  }
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});
  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthService()),
      ChangeNotifierProvider(create: (_) => LiveTrackingCoordinator()),
    ],
    child: MaterialApp(
      navigatorKey: appNavigatorKey,
      navigatorObservers: [employeeRouteSignal],
      debugShowCheckedModeBanner: false,
      title: 'GoDigital Attendance',
      builder: (context, child) => AuthSessionGuard(
        child: FieldWaitingPromptHost(
          child: child ?? const SizedBox.shrink(),
          navigatorKey: appNavigatorKey,
          routeRevision: employeeRouteSignal.revision,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const AuthGate(),
        '/home': (_) => const AttendanceEntry(),
        '/attendance': (_) => const AttendanceEntry(),
        '/employee/dashboard': (_) => const EmployeeDashboardPage(),
        '/employee/attendance': (_) => const EmployeeAttendancePage(),
        '/employee/clock-log': (_) => const EmployeeClockPage(),
        '/employee/leave': (_) => const EmployeeLeavePage(),
        '/employee/permission': (_) => const EmployeePermissionPage(),
        '/employee/extra-hours': (_) => const EmployeeExtraHoursPage(),
        '/employee/salary': (_) => const EmployeeSalaryPage(),
        '/employee/tracking': (_) => const EmployeeTrackingPage(),
        '/employee/profile': (_) => const EmployeeProfilePage(),
      },
      // The admin portal is a nested MaterialApp. Register its deep links in
      // the root app too, so a browser refresh or Flutter hot restart while
      // on /admin/dashboard can rebuild the portal instead of falling back to
      // the login route.
      onGenerateRoute: (settings) {
        if (settings.name?.startsWith('/admin/') ?? false) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const AttendanceEntry(),
          );
        }
        return null;
      },
    ),
  );
}

class AuthSessionGuard extends StatefulWidget {
  const AuthSessionGuard({super.key, required this.child});
  final Widget child;

  @override
  State<AuthSessionGuard> createState() => _AuthSessionGuardState();
}

class _AuthSessionGuardState extends State<AuthSessionGuard>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _verify());
    WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
  }

  Future<void> _verify() async {
    if (_checking || !mounted) return;
    final auth = context.read<AuthService>();
    if (!auth.isInitialized || !auth.isAuthenticated) return;
    _checking = true;
    try {
      await auth.verifyToken();
    } finally {
      _checking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _verify();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => Consumer<AuthService>(
    builder: (_, auth, _) {
      if (!auth.isInitialized)
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return auth.isAuthenticated
          ? const AttendanceEntry()
          : const LoginScreen();
    },
  );
}

class AttendanceEntry extends StatelessWidget {
  const AttendanceEntry({super.key});
  @override
  Widget build(BuildContext context) => Consumer<AuthService>(
    builder: (_, auth, _) {
      if (!auth.isAuthenticated) return const LoginScreen();
      return auth.userType?.toLowerCase().trim() == 'admin'
          ? hrms_admin.AdminPortalApp()
          : const EmployeeDashboardPage();
    },
  );
}

