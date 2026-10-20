import 'package:flutter/material.dart';
/// Provides the fixed, light GoDigital admin appearance.
class AdminAppearanceController extends ChangeNotifier {
  static const Color _accent = Color(0xFFE3162A);
  bool _ready = false;

  Color get accent => _accent;
  bool get ready => _ready;
  Brightness get brightness => Brightness.light;

  Future<void> load() async {
    _ready = true;
    notifyListeners();
  }
}
