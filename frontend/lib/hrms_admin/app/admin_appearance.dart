import 'package:flutter/material.dart';

/// The fixed default appearance of the admin workspace.
class AdminAppearanceController extends ChangeNotifier {
  Color get accent => const Color(0xFF1769E0);
  Color get background => const Color(0xFFF7F9FD);
  Color get card => Colors.white;
  Color get text => const Color(0xFF102653);
  Color get border => const Color(0xFFE1E7F0);
  Brightness get brightness => Brightness.light;
}
