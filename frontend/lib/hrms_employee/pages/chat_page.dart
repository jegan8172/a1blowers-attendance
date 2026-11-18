import 'package:flutter/material.dart';
import '../../features/chat/chat_page.dart' as chat;
import '../shared/employee_ui.dart';

class EmployeeChatPage extends StatelessWidget {
  const EmployeeChatPage({super.key});
  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      bottomNavigationBar:
          mobile ? const EmployeeMobileBottomNav(route: '/employee/chat') : null,
      body: SafeArea(
        child: Column(
          children: [
            // Chat already has its own conversation header. Keep the global
            // employee navigation on larger screens, but remove it on mobile
            // so the message list has the available height.
            if (!mobile) const EmployeeTopNavigation(route: '/employee/chat'),
            const Expanded(child: chat.ChatPage()),
          ],
        ),
      ),
    );
  }
}
