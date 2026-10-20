import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A quiet, theme-coloured pattern behind admin content.
class AdminPatternBackground extends StatelessWidget {
  const AdminPatternBackground({super.key, required this.child, this.global = false});

  final Widget child;
  final bool global;

  @override
  Widget build(BuildContext context) => !global && context.dependOnInheritedWidgetOfExactType<_GlobalPattern>() != null ? child : _GlobalPattern(child: Stack(
    fit: StackFit.expand,
    children: [
      IgnorePointer(
        child: RepaintBoundary(child: CustomPaint(
          painter: _PatternPainter(Theme.of(context).colorScheme.primary),
          isComplex: true,
        )),
      ),
      child,
    ],
  ));
}

class _GlobalPattern extends InheritedWidget {
  const _GlobalPattern({required super.child});
  @override
  bool updateShouldNotify(_GlobalPattern oldWidget) => false;
}

class _PatternPainter extends CustomPainter {
  const _PatternPainter(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width, 1200.0);
    final centre = Offset(size.width * .83, size.height * .40);
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4;
    for (var i = 0; i < 16; i++) {
      final radius = unit * (.12 + i * .008);
      paint.color = accent.withValues(alpha: .30 + .18 * (1 - i / 16));
      canvas.drawArc(Rect.fromCircle(center: centre, radius: radius),
        -math.pi * .85, math.pi * 1.48, false, paint);
    }
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final spacing = math.max(8.0, unit * .012);
    for (var row = 0; row < 16; row++) {
      for (var col = 0; col < 17; col++) {
        final distance = math.sqrt(math.pow(row - 7.5, 2) + math.pow(col - 8, 2));
        if (distance > 8) continue;
        dotPaint.color = accent.withValues(alpha: .48 * (1 - distance / 9));
        canvas.drawCircle(Offset(size.width * .10 + col * spacing,
          size.height * .68 + row * spacing), 2.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) => oldDelegate.accent != accent;
}
