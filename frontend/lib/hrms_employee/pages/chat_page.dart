import 'package:flutter/material.dart';
import '../../features/chat/chat_page.dart' as chat;
import '../shared/employee_ui.dart';

class EmployeeChatPage extends StatelessWidget {
  const EmployeeChatPage({super.key});
  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      bottomNavigationBar: mobile
          ? const EmployeeMobileBottomNav(route: '/employee/chat')
          : null,
      body: SafeArea(
        child: Column(
          children: [
            // Keep the employee header visible on mobile too. It anchors the
            // chat surface to the rest of the portal and matches every other
            // employee page's navigation model.
            EmployeeTopNavigation(route: '/employee/chat', mobile: mobile),
            const Expanded(child: chat.ChatPage()),
          ],
        ),
      ),
    );
  }
}
