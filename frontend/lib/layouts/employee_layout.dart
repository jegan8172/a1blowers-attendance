import 'package:flutter/material.dart';
import 'package:godigital_portal/core/constants/employee_role.dart';
import 'package:godigital_portal/core/widgets/employee_sidebar.dart';
import 'package:godigital_portal/core/widgets/employee_topbar.dart';

class EmployeeLayout extends StatelessWidget {
  final String selectedMenu;
  final EmployeeRole role;
  final Widget child;
  final Function(String) onMenuTap;

  const EmployeeLayout({
    super.key,
    required this.selectedMenu,
    required this.role,
    required this.child,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA), // Match admin style
      body: Row(
        children: [
          EmployeeSidebar(
            selectedMenu: selectedMenu,
            menuItems: role.menuItems,
            onMenuTap: onMenuTap,
          ),
          Expanded(
            child: Column(
              children: [
                EmployeeTopbar(role: role),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(28), // Consistent content padding
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}