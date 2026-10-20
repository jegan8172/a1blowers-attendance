import 'package:flutter/material.dart';
import 'package:hrms_design_system/hrms_design_system.dart';
import 'package:provider/provider.dart';

import 'admin_appearance.dart';
import '../routing/app_router.dart';
import '../shared/widgets/admin_pattern_background.dart';

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
    _appearance = AdminAppearanceController();
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
        builder: (context, child) => ColoredBox(color: appearance.background,
          child: AdminPatternBackground(global: true, child: child ?? const SizedBox.shrink())),
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
      brightness: appearance.brightness,
    ).copyWith(
      surface: appearance.card,
      surfaceContainerHighest: Color.alphaBlend(appearance.text.withValues(alpha: .04), appearance.card),
      onSurface: appearance.text,
      onSurfaceVariant: appearance.text.withValues(alpha: .72),
      outline: appearance.border,
    );
    final base = HrmsTheme.light();
    return base.copyWith(
      colorScheme: scheme,
      textTheme: base.textTheme.apply(bodyColor: appearance.text, displayColor: appearance.text),
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: appearance.card,
        foregroundColor: appearance.text,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: appearance.card,
      ),
      dividerTheme: DividerThemeData(
        color: appearance.border,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: appearance.card,
        hintStyle: TextStyle(
          color: appearance.text.withValues(alpha: .72),
        ),
        labelStyle: TextStyle(
          color: appearance.text.withValues(alpha: .72),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: appearance.border,
          ),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: appearance.card,
        titleTextStyle: TextStyle(
          color: appearance.text,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
        contentTextStyle: TextStyle(
          color: appearance.text.withValues(alpha: .72),
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
