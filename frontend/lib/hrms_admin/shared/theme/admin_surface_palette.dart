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
    final scheme = Theme.of(context).colorScheme;
    return AdminSurfacePalette._(
      surface: scheme.surface,
      subtleSurface: scheme.surfaceContainerHighest,
      text: scheme.onSurface,
      mutedText: scheme.onSurfaceVariant,
      border: scheme.outline,
    );
  }
}
