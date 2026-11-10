import 'package:flutter/material.dart';

/// Provides the shared admin background boundary without decorative artwork.
class AdminPatternBackground extends StatelessWidget {
  const AdminPatternBackground({super.key, required this.child, this.global = false});

  final Widget child;
  final bool global;

  @override
  Widget build(BuildContext context) => !global && context.dependOnInheritedWidgetOfExactType<_GlobalPattern>() != null
      ? child
      : _GlobalPattern(child: child);
}

class _GlobalPattern extends InheritedWidget {
  const _GlobalPattern({required super.child});
  @override
  bool updateShouldNotify(_GlobalPattern oldWidget) => false;
}
