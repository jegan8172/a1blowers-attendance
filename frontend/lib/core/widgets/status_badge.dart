import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class StatusBadge extends StatelessWidget {
  final String text;

  const StatusBadge({
    super.key,
    required this.text,
  });

  Color get badgeColor {
    // Handling cases used in your dashboard
    switch (text.toUpperCase()) {
      case 'COMPLETED':
        return AppColors.green;
      case 'SUBMITTED':
        return AppColors.green;
      case 'REVIEW':
        return Colors.purple;
      case 'ON HOLD':
        return Colors.orange; // Changed to orange to match alerts/warnings
      case 'IN PROGRESS':
        return AppColors.primary;
      case 'DONE':
        return Colors.blue;
      case 'REJECTED':
        return AppColors.red;
      default:
        return AppColors.textGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    // If the text is empty or just a dash, show simple text
    if (text == '-' || text.isEmpty) {
      return const Text('-', style: TextStyle(color: AppColors.textGrey));
    }

    return Container(
      // Ensure vertical padding is tight for a professional look
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4), // Added rounded corners
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: badgeColor,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}