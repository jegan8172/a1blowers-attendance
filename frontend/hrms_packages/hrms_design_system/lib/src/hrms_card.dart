import 'package:flutter/material.dart';
import 'colors.dart';

/// Generic card shell used across KPI cards, list-to-card table rows,
/// section panels, etc. Matches the rounded, softly-bordered white card
/// used throughout the approved reference screens.
class HrmsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const HrmsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: HrmsColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HrmsColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x08101D3B), blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: child,
    );
  }
}
