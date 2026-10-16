import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTextStyles {
  static const TextStyle heading = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: AppColors.textDark,
  );

  static const TextStyle subHeading = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textGrey,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  static const TextStyle cardNumber = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w800,
    color: AppColors.textDark,
  );

  static const TextStyle tableHeader = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    color: Color(0xFF172554),
  );

  static const TextStyle tableText = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textDark,
  );
}