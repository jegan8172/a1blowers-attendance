import 'package:flutter/material.dart';
import 'package:hrms_design_system/hrms_design_system.dart';
import 'package:hrms_responsive/hrms_responsive.dart';
import 'employee_nav.dart';

/// Responsive app shell per HRMS_PROJECT_BLUEPRINT.md, Section 3
/// (Employee, revised 2026-08-28):
/// - Desktop/Tablet: top navigation bar, same pattern as Admin — no left
///   sidebar (supersedes the earlier sidebar design).
/// - Mobile: no persistent nav at all. The Dashboard is the hub; other
///   pages are reached one level deep from it and use the platform back
///   button to return — no drawer, no bottom nav.
class EmployeeShell extends StatelessWidget {
  final Widget body;
  final EmployeeNavItem current;

  const EmployeeShell({super.key, required this.body, required this.current});

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      mobile: (context) => _MobileShell(current: current, body: body),
      tablet: (context) => _TopNavShell(current: current, body: body),
      desktop: (context) => _TopNavShell(current: current, body: body),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: HrmsColors.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child:
              const Icon(Icons.diamond_outlined, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        const Text(
          'GO DIGITAL',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: HrmsColors.primary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _NavPill extends StatelessWidget {
  final EmployeeNavItem current;
  const _NavPill({required this.current});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: HrmsColors.pageBackground,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: EmployeeNavItem.values.map((item) {
          final isActive = item == current;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: isActive ? HrmsColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  if (!isActive) {
                    Navigator.of(context).pushReplacementNamed(item.route);
                  }
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: isActive ? Colors.white : HrmsColors.textSecondary,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Live-time + Checked-in status chips, shown in the employee top bar on
/// desktop/tablet (see images 14-20) — not present on Admin or on the
/// employee mobile app, which shows check-in state on the Dashboard card
/// instead.
class _StatusChips extends StatelessWidget {
  const _StatusChips();

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final label = now.format(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chip(label, HrmsColors.infoBg, HrmsColors.info),
        const SizedBox(width: 8),
        _chip('Checked In', HrmsColors.infoBg, HrmsColors.primary, dot: true),
      ],
    );
  }

  Widget _chip(String text, Color bg, Color fg, {bool dot = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(text,
              style: TextStyle(
                  color: fg, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}

class _BellIcon extends StatelessWidget {
  const _BellIcon();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
              color: HrmsColors.pageBackground, shape: BoxShape.circle),
          child: const Icon(Icons.notifications_none,
              color: HrmsColors.textSecondary),
        ),
        Positioned(
          top: 6,
          right: 8,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: HrmsColors.danger, shape: BoxShape.circle),
          ),
        ),
      ],
    );
  }
}

class _TopNavShell extends StatelessWidget {
  final EmployeeNavItem current;
  final Widget body;

  const _TopNavShell({required this.current, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: const BoxDecoration(
              color: HrmsColors.surface,
              border: Border(bottom: BorderSide(color: HrmsColors.border)),
            ),
            child: Row(
              children: [
                const _Logo(),
                const SizedBox(width: 20),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _NavPill(current: current),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                const _StatusChips(),
                const SizedBox(width: 16),
                const _BellIcon(),
                const SizedBox(width: 12),
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: HrmsColors.infoBg,
                  child:
                      Icon(Icons.person, color: HrmsColors.primary, size: 20),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _MobileShell extends StatelessWidget {
  final EmployeeNavItem current;
  final Widget body;

  const _MobileShell({required this.current, required this.body});

  @override
  Widget build(BuildContext context) {
    // No drawer, no bottom nav — per the revised spec the Dashboard is the
    // hub and every other page is reached one level deep from it, using
    // the platform back button (auto-added leading arrow) to return.
    return Scaffold(
      appBar: AppBar(
        title: const _Logo(),
        actions: const [
          _BellIcon(),
          SizedBox(width: 12),
          CircleAvatar(
            radius: 16,
            backgroundColor: HrmsColors.infoBg,
            child: Icon(Icons.person, color: HrmsColors.primary, size: 18),
          ),
          SizedBox(width: 12),
        ],
      ),
      body: body,
    );
  }
}
