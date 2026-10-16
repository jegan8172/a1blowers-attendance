import 'package:flutter/material.dart';
import 'colors.dart';
import 'hrms_card.dart';

/// KPI summary card — icon chip, big number, label, subtitle and a thin
/// colored underline. Matches the Admin Dashboard / Employees / Approvals /
/// Payroll / Tracking KPI row in the approved reference screens.
///
/// Responsive placement (4 cols desktop / 2 cols tablet & mobile / 1 col on
/// very narrow devices) is handled by the grid that lays these out, per
/// HRMS_PROJECT_BLUEPRINT.md, Section 3 — not by this widget itself.
class KpiCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String value;
  final String label;
  final String subtitle;

  const KpiCard({
    super.key,
    required this.icon,
    required this.accent,
    required this.value,
    required this.label,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return HrmsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: HrmsColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: HrmsColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: HrmsColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Container(height: 3, width: 32, color: accent),
        ],
      ),
    );
  }
}
