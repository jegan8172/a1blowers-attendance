import 'package:flutter/material.dart';
import 'package:hrms_design_system/hrms_design_system.dart';
import 'package:hrms_responsive/hrms_responsive.dart';
import 'admin_nav.dart';

/// Responsive app shell per HRMS_PROJECT_BLUEPRINT.md, Section 3 (Admin):
/// - Desktop/Tablet: approved top navigation pill (no permanent sidebar).
/// - Mobile: logo, notification icon, avatar and a menu button opening a
///   drawer with the same nav items.
///
/// Visual styling (nav pill, colors, avatar) follows the approved
/// reference screens (Admin Dashboard / Employees / Approvals / Payroll /
/// Tracking).
class AdminShell extends StatelessWidget {
  final Widget body;
  final AdminNavItem current;

  const AdminShell({super.key, required this.body, required this.current});

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      mobile: (context) => _MobileShell(current: current, body: body),
      tablet: (context) => _DesktopTopNavShell(current: current, body: body),
      desktop: (context) => _DesktopTopNavShell(current: current, body: body),
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
  final AdminNavItem current;

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
        children: AdminNavItem.values.map((item) {
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
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: isActive ? Colors.white : HrmsColors.textSecondary,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
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

class _AvatarWithBell extends StatelessWidget {
  const _AvatarWithBell();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BellIcon(),
        const SizedBox(width: 16),
        const CircleAvatar(
          radius: 18,
          backgroundColor: HrmsColors.infoBg,
          child: Icon(Icons.person, color: HrmsColors.primary, size: 20),
        ),
      ],
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
                color: HrmsColors.primary, shape: BoxShape.circle),
          ),
        ),
      ],
    );
  }
}

class _DesktopTopNavShell extends StatelessWidget {
  final AdminNavItem current;
  final Widget body;

  const _DesktopTopNavShell({required this.current, required this.body});

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
                const SizedBox(width: 24),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _NavPill(current: current),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                const _AvatarWithBell(),
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
  final AdminNavItem current;
  final Widget body;

  const _MobileShell({required this.current, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const _Logo(),
        actions: [
          const _BellIcon(),
          const SizedBox(width: 12),
          const CircleAvatar(
            radius: 16,
            backgroundColor: HrmsColors.infoBg,
            child: Icon(Icons.person, color: HrmsColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
        ],
      ),
      // Menu button (leading, auto-added by Scaffold) opens this drawer —
      // same nav items as desktop, per Section 3.
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const Padding(padding: EdgeInsets.all(20), child: _Logo()),
              for (final item in AdminNavItem.values)
                ListTile(
                  selected: item == current,
                  selectedTileColor: HrmsColors.infoBg,
                  title: Text(item.label),
                  onTap: () {
                    Navigator.of(context).pop();
                    if (item != current) {
                      Navigator.of(context).pushReplacementNamed(item.route);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
      body: body,
    );
  }
}
