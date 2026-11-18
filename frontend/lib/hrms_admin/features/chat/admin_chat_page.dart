import 'package:flutter/material.dart';

import '../../../features/chat/chat_page.dart';
import '../../shared/widgets/admin_top_nav.dart';

class AdminChatPage extends StatelessWidget {
  const AdminChatPage({super.key});

  static Widget builder(BuildContext context) => const AdminChatPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Colors.transparent,
        bottomNavigationBar: AdminMobileBottomNav(activeRoute: '/admin/chat'),
        body: Column(
          children: [
            AdminTopNav(activeRoute: '/admin/chat'),
            Expanded(child: ChatPage()),
          ],
        ),
      );
}
