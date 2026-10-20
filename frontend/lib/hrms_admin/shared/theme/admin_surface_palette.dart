import 'package:flutter/material.dart';

/// The shared neutral palette for every admin workspace screen.
///
/// Feature pages should use these fixed light-theme values instead of the
/// red-derived Material surface colours, which otherwise tint cards pink.
@immutable
class AdminSurfacePalette {
  const AdminSurfacePalette._({
    required this.surface,
    required this.subtleSurface,
    required this.text,
    required this.mutedText,
    required this.border,
  });

  final Color surface;
  final Color subtleSurface;
  final Color text;
  final Color mutedText;
  final Color border;

  factory AdminSurfacePalette.of(BuildContext context) {
    return AdminSurfacePalette._(
      surface: Colors.white,
      subtleSurface: const Color(0xFFF9FBFE),
      text: const Color(0xFF102653),
      mutedText: const Color(0xFF647493),
      border: const Color(0xFFE1E7F0),
    );
  }
}
