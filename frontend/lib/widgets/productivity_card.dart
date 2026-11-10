
// lib/widgets/productivity_card.dart

import 'package:flutter/material.dart';

import 'package:godigital_portal/core/constants/app_colors.dart';

class ProductivityCard extends StatelessWidget {
  final int approved;
  final int rework;
  final int rejected;
  final int review;
  final int others;

  const ProductivityCard({
    super.key,
    required this.approved,
    required this.rework,
    required this.rejected,
    required this.review,
    required this.others,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0757D5).withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 330;

          Widget liveBadge() {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: const Color(0xFFDCFCE7)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.trending_up_rounded, size: 11, color: Color(0xFF16A34A)),
                  SizedBox(width: 3),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      fontSize: 7.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF16A34A),
                      letterSpacing: .4,
                    ),
                  ),
                ],
              ),
            );
          }

          Widget titleBlock() {
            return Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daily Productivity',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textDark,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Today\'s performance overview',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            );
          }

          Widget iconBox() {
            return Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0757D5), Color(0xFF3B82F6)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0757D5).withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.insights_rounded, color: Colors.white, size: 18),
            );
          }

          Widget header() {
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [iconBox(), const SizedBox(width: 10), titleBlock()]),
                  const SizedBox(height: 8),
                  liveBadge(),
                ],
              );
            }

            return Row(
              children: [
                iconBox(),
                const SizedBox(width: 10),
                titleBlock(),
                const SizedBox(width: 8),
                liveBadge(),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header(),
              const SizedBox(height: 12),
              _ProductivityItem(
                title: 'Approved',
                value: approved.toString(),
                color: AppColors.green,
                icon: Icons.check_circle_rounded,
              ),
              _ProductivityItem(
                title: 'Rejected',
                value: rejected.toString(),
                color: AppColors.red,
                icon: Icons.cancel_rounded,
              ),
              _ProductivityItem(
                title: 'Reworks',
                value: rework.toString(),
                color: Colors.orange,
                icon: Icons.replay_circle_filled_rounded,
              ),
              _ProductivityItem(
                title: 'Review',
                value: review.toString(),
                color: Colors.purple,
                icon: Icons.rate_review_rounded,
              ),
              _ProductivityItem(
                title: 'Others',
                value: others.toString(),
                color: AppColors.textGrey,
                icon: Icons.more_horiz_rounded,
              ),
            ],
          );
        },
      ),
    );
  }}


// ============================================================
// PRODUCTIVITY ITEM
// ============================================================

class _ProductivityItem extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _ProductivityItem({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final number = int.tryParse(value) ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Builder(
          builder: (context) {
            return _HoverProductivityItem(
              title: title,
              value: value,
              color: color,
              icon: icon,
              number: number,
            );
          },
        ),
      ),
    );
  }
}


// ============================================================
// HOVER ITEM
// ============================================================

class _HoverProductivityItem extends StatefulWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final int number;

  const _HoverProductivityItem({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    required this.number,
  });

  @override
  State<_HoverProductivityItem> createState() =>
      _HoverProductivityItemState();
}

class _HoverProductivityItemState
    extends State<_HoverProductivityItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _hovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          _hovered = false;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,

        transform: Matrix4.translationValues(
          _hovered ? 2 : 0,
          0,
          0,
        ),

        padding: const EdgeInsets.symmetric(
          horizontal: 7,
          vertical: 2,
        ),

        decoration: BoxDecoration(
          color: _hovered
              ? colorWithAlpha(widget.color, 0.055)
              : Colors.transparent,

          borderRadius: BorderRadius.circular(9),

          border: Border.all(
            color: _hovered
                ? colorWithAlpha(widget.color, 0.14)
                : Colors.transparent,
          ),

          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: colorWithAlpha(
                      widget.color,
                      0.10,
                    ),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),

        child: Row(
          children: [
            // =================================================
            // ICON
            // =================================================

            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 25,
              height: 25,

              decoration: BoxDecoration(
                color: colorWithAlpha(
                  widget.color,
                  _hovered ? 0.16 : 0.09,
                ),
                borderRadius: BorderRadius.circular(8),

                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: colorWithAlpha(
                            widget.color,
                            0.18,
                          ),
                          blurRadius: 8,
                        ),
                      ]
                    : [],
              ),

              child: AnimatedScale(
                duration: const Duration(milliseconds: 180),
                scale: _hovered ? 1.12 : 1.0,
                child: Icon(
                  widget.icon,
                  size: 14,
                  color: widget.color,
                ),
              ),
            ),

            const SizedBox(width: 8),

            // =================================================
            // TITLE
            // =================================================

            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
            ),

            // =================================================
            // MINI PROGRESS INDICATOR
            // =================================================

            SizedBox(
              width: 38,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 4,

                  value: widget.number > 0
                      ? 0.65
                      : 0,

                  backgroundColor:
                      const Color(0xFFEFF2F6),

                  valueColor:
                      AlwaysStoppedAnimation<Color>(
                    widget.color.withValues(
                      alpha: _hovered ? 0.75 : 0.50,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // =================================================
            // NUMBER BADGE
            // =================================================

            AnimatedContainer(
              duration: const Duration(milliseconds: 180),

              constraints: const BoxConstraints(
                minWidth: 27,
              ),

              padding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 3,
              ),

              decoration: BoxDecoration(
                color: widget.color.withValues(
                  alpha: _hovered ? 0.15 : 0.10,
                ),
                borderRadius: BorderRadius.circular(6),

                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: widget.color.withValues(
                            alpha: 0.15,
                          ),
                          blurRadius: 7,
                        ),
                      ]
                    : [],
              ),

              child: Text(
                widget.value,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: widget.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color colorWithAlpha(
    Color color,
    double opacity,
  ) {
    return color.withValues(alpha: opacity);
  }
}
