import 'package:flutter/material.dart';
import '../../features/chat/chat_page.dart' as chat;
import '../shared/employee_ui.dart';

class EmployeeChatPage extends StatelessWidget {
  const EmployeeChatPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: MediaQuery.sizeOf(context).width < 600
      ? const EmployeeMobileBottomNav(route: '/employee/chat') : null,
    body: SafeArea(child: Column(children: const [
      EmployeeTopNavigation(route: '/employee/chat'),
      Expanded(child: chat.ChatPage()),
    ])),
  );
}
