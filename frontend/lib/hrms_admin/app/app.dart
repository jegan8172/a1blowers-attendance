import 'package:flutter/material.dart';
import 'package:hrms_design_system/hrms_design_system.dart';
import 'package:provider/provider.dart';

import 'admin_appearance.dart';
import '../routing/app_router.dart';

class AdminPortalApp extends StatefulWidget {
  const AdminPortalApp({super.key});

  @override
  State<AdminPortalApp> createState() => _AdminPortalAppState();
}

class _AdminPortalAppState extends State<AdminPortalApp> {
  late final AdminAppearanceController _appearance;

  @override
  void initState() {
    super.initState();
    _appearance = AdminAppearanceController()..load();
  }

  @override
  void dispose() {
    _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: _appearance,
    child: Consumer<AdminAppearanceController>(
      builder: (_, appearance, __) => MaterialApp(
        title: 'A1 Blowers HRMS — Admin',
        theme: _themeFor(appearance),
        initialRoute: '/admin/dashboard',
        routes: AppRouter.routes,
        debugShowCheckedModeBanner: false,
      ),
    ),
  );

  ThemeData _themeFor(AdminAppearanceController appearance) {
    final scheme = ColorScheme.fromSeed(
      seedColor: appearance.accent,
      primary: appearance.accent,
      brightness: Brightness.light,
    ).copyWith(
      surface: Colors.white,
      surfaceContainerHighest: const Color(0xFFF9FBFE),
      onSurface: const Color(0xFF102653),
      onSurfaceVariant: const Color(0xFF647493),
      outline: const Color(0xFFE1E7F0),
    );
    final base = HrmsTheme.light();
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF7F9FD),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF102653),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: Colors.white,
      ),
      dividerTheme: DividerThemeData(
        color: const Color(0xFFE1E7F0),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: TextStyle(
          color: const Color(0xFF647493),
        ),
        labelStyle: TextStyle(
          color: const Color(0xFF647493),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: const Color(0xFFE1E7F0),
          ),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: Colors.white,
        titleTextStyle: TextStyle(
          color: const Color(0xFF102653),
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
        contentTextStyle: TextStyle(
          color: const Color(0xFF647493),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: appearance.accent, foregroundColor: Colors.white),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: appearance.accent, foregroundColor: Colors.white),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? appearance.accent : null),
        trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? appearance.accent.withValues(alpha: .38) : null),
      ),
    );
  }
}
