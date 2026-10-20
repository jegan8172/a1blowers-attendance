import 'package:flutter/material.dart';
import 'colors.dart';

/// Labeled dropdown-look button used in filter bars (Approvals' Employee/
/// Date/Status filters, Employees' Department/Status/Work Mode filters).
/// Not a real dropdown yet — wiring actual selection happens once the
/// corresponding list/query API (Section 6) is connected.
class FilterDropdown extends StatelessWidget {
  final String? label;
  final String value;
  final IconData? leading;
  final VoidCallback? onTap;

  const FilterDropdown({
    super.key,
    this.label,
    required this.value,
    this.leading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!, style: const TextStyle(color: HrmsColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
        ],
        Material(
          color: HrmsColors.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap ?? () {},
            child: Container(
              constraints: const BoxConstraints(minWidth: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: HrmsColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) ...[
                    Icon(leading, size: 16, color: HrmsColors.textSecondary),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.keyboard_arrow_down, size: 18, color: HrmsColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
