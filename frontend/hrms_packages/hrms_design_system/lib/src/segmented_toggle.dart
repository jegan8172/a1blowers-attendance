import 'package:flutter/material.dart';
import 'colors.dart';

class SegmentOption {
  final String label;
  final int? count;
  const SegmentOption(this.label, {this.count});
}

/// Pill-style segmented toggle — used for Approvals' Leave Requests/Extra
/// Hours tabs and Tracking's Office/Home/Field switch. Active segment is
/// filled with [activeColor] (defaults to primary blue; Tracking uses
/// green for its Field-mode active state in the reference screens).
class SegmentedToggle extends StatelessWidget {
  final List<SegmentOption> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Color activeColor;

  const SegmentedToggle({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
    this.activeColor = HrmsColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(options.length, (i) {
        final isActive = i == selectedIndex;
        final option = options[i];
        return Material(
          color: isActive ? activeColor : HrmsColors.surface,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => onChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isActive ? activeColor : HrmsColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    option.label,
                    style: TextStyle(
                      color: isActive ? Colors.white : HrmsColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (option.count != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.white.withValues(alpha: 0.25) : HrmsColors.neutralBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${option.count}',
                        style: TextStyle(
                          color: isActive ? Colors.white : HrmsColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
