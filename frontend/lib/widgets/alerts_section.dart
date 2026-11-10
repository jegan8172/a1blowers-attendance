
// lib/widgets/alerts_section.dart

import 'package:flutter/material.dart';
import 'package:godigital_portal/core/constants/app_colors.dart';

class AlertsSection extends StatefulWidget {
  final List<Map<String, dynamic>> notifications;
  final VoidCallback? onViewAll;

  const AlertsSection({
    super.key,
    required this.notifications,
    this.onViewAll,
  });

  @override
  State<AlertsSection> createState() => _AlertsSectionState();
}

class _AlertsSectionState extends State<AlertsSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        height: 235,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  "Recent Alerts",
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textDark,
                  ),
                ),

                const Spacer(),

                InkWell(
                  onTap: widget.onViewAll,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      "View All Notifications",
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Expanded(
              child: widget.notifications.isEmpty
                  ? const Center(
                      child: Text(
                        "No recent alerts found",
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : Row(
                      children: List.generate(
                        widget.notifications.length > 3
                            ? 3
                            : widget.notifications.length,
                        (index) {
                          final item = widget.notifications[index];

                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: index == 2 ? 0 : 14,
                              ),
                              child: _AlertCard(
                                icon: _icon(item["category"]),
                                color: _color(item["category"]),
                                title: item["category"] ?? "",
                                message: item["preview"] ?? "",
                                time: item["createdAt"] ?? "",
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(String? category) {
    switch (category) {
      case "Task Assigned":
        return Icons.assignment_rounded;

      case "Task Review":
        return Icons.fact_check_rounded;

      case "Warning & Alert":
        return Icons.warning_amber_rounded;

      case "Daily Planner":
        return Icons.calendar_today_rounded;

      case "Content Shared":
        return Icons.share_rounded;

      default:
        return Icons.notifications_rounded;
    }
  }

  static Color _color(String? category) {
    switch (category) {
      case "Task Assigned":
        return AppColors.primary;

      case "Task Review":
        return Colors.green;

      case "Warning & Alert":
        return Colors.red;

      case "Daily Planner":
        return Colors.orange;

      case "Content Shared":
        return Colors.purple;

      default:
        return Colors.grey;
    }
  }
}


// ============================================================
// PREMIUM HOVER ALERT CARD
// ============================================================

class _AlertCard extends StatefulWidget{
  final IconData icon;
  final String title;
  final String message;
  final String time;
  final Color color;

  const _AlertCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.time,
    required this.color,
  });

  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;

  late AnimationController _iconController;

  @override
  void initState() {
    super.initState();

    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
  }

  @override
  void dispose() {
    _iconController.dispose();
    super.dispose();
  }

  void _onHover(bool value) {
    setState(() {
      _isHovered = value;
    });

    if (value) {
      _iconController.forward();
    } else {
      _iconController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _onHover(true),
      onExit: (_) => _onHover(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,

        transform: Matrix4.translationValues(
          0,
          _isHovered ? -4 : 0,
          0,
        ),

        padding: const EdgeInsets.all(13),

        decoration: BoxDecoration(
          color: _isHovered
              ? Colors.white
              : AppColors.lightBlue,

          borderRadius: BorderRadius.circular(12),

          border: Border.all(
            color: _isHovered
                ? widget.color.withValues(alpha: 0.28)
                : AppColors.border.withValues(alpha: 0.6),
          ),

          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.14),
                    blurRadius: 20,
                    spreadRadius: 1,
                    offset: const Offset(0, 7),
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.8),
                    blurRadius: 5,
                    offset: const Offset(0, -2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.015),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),

        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==================================================
            // ACCENT LIGHT BAR
            // ==================================================

            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: _isHovered ? 5 : 4,
              height: double.infinity,

              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(3),

                boxShadow: _isHovered
                    ? [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.45),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
            ),

            const SizedBox(width: 9),

            // ==================================================
            // ANIMATED ICON
            // ==================================================

            AnimatedBuilder(
              animation: _iconController,
              builder: (context, child) {
                final scale = 1.0 +
                    (_iconController.value * 0.10);

                return Transform.scale(
                  scale: scale,
                  child: Transform.rotate(
                    angle: _iconController.value * 0.05,
                    child: child,
                  ),
                );
              },

              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),

                padding: const EdgeInsets.all(7),

                decoration: BoxDecoration(
                  color: widget.color.withValues(
                    alpha: _isHovered ? 0.18 : 0.12,
                  ),

                  borderRadius: BorderRadius.circular(9),

                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: widget.color.withValues(
                              alpha: 0.20,
                            ),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ]
                      : [],
                ),

                child: Icon(
                  widget.icon,
                  color: widget.color,
                  size: _isHovered ? 18 : 17,
                ),
              ),
            ),

            const SizedBox(width: 10),

            // ==================================================
            // CONTENT
            // ==================================================

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),

                      // Small animated indicator
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: _isHovered ? 6 : 4,
                        height: _isHovered ? 6 : 4,
                        decoration: BoxDecoration(
                          color: widget.color,
                          shape: BoxShape.circle,

                          boxShadow: _isHovered
                              ? [
                                  BoxShadow(
                                    color: widget.color.withValues(
                                      alpha: 0.45,
                                    ),
                                    blurRadius: 5,
                                  ),
                                ]
                              : [],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 3),

                  Expanded(
                    child: Text(
                      widget.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  const SizedBox(height: 4),

                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 10,
                        color: AppColors.textGrey.withValues(
                          alpha: 0.75,
                        ),
                      ),

                      const SizedBox(width: 4),

                      Expanded(
                        child: Text(
                          widget.time,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textGrey.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ==================================================
            // HOVER ARROW
            // ==================================================

            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: _isHovered ? 17 : 0,

              child: _isHovered
                  ? const Align(
                      alignment: Alignment.centerRight,
                      child: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 10,
                        color: AppColors.primary,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
