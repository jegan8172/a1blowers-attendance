import 'package:flutter/material.dart';
import 'colors.dart';

enum HrmsStatusTone { success, warning, danger, info, neutral }

/// Status chip used for Attendance/Request/Payroll/Employee states —
/// e.g. Approved, Pending, Rejected, Active, On Leave, Processed.
/// Pass [tone] directly, or use [HrmsStatusTone.fromLabel] to infer it
/// from a common status word.
class StatusBadge extends StatelessWidget {
  final String label;
  final HrmsStatusTone tone;

  const StatusBadge({super.key, required this.label, required this.tone});

  factory StatusBadge.fromLabel(String label) {
    final normalized = label.toLowerCase();
    HrmsStatusTone tone;
    if (['approved', 'active', 'present', 'processed', 'paid', 'working', 'marked']
        .any(normalized.contains)) {
      tone = HrmsStatusTone.success;
    } else if (['pending', 'late', 'half', 'processing'].any(normalized.contains)) {
      tone = HrmsStatusTone.warning;
    } else if (['rejected', 'absent', 'denied', 'inactive', 'failed', 'missed']
        .any(normalized.contains)) {
      tone = HrmsStatusTone.danger;
    } else if (['on leave', 'leave'].any(normalized.contains)) {
      tone = HrmsStatusTone.info;
    } else {
      tone = HrmsStatusTone.neutral;
    }
    return StatusBadge(label: label, tone: tone);
  }

  ({Color fg, Color bg}) _colors() {
    switch (tone) {
      case HrmsStatusTone.success:
        return (fg: HrmsColors.success, bg: HrmsColors.successBg);
      case HrmsStatusTone.warning:
        return (fg: HrmsColors.warning, bg: HrmsColors.warningBg);
      case HrmsStatusTone.danger:
        return (fg: HrmsColors.danger, bg: HrmsColors.dangerBg);
      case HrmsStatusTone.info:
        return (fg: HrmsColors.info, bg: HrmsColors.infoBg);
      case HrmsStatusTone.neutral:
        return (fg: HrmsColors.neutral, bg: HrmsColors.neutralBg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: c.fg, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
