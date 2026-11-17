class ChatNavigation {
  ChatNavigation._();

  static int? _pendingConversationId;

  static void openConversation(int conversationId) {
    if (conversationId > 0) _pendingConversationId = conversationId;
  }

  static int? takePendingConversationId() {
    final value = _pendingConversationId;
    _pendingConversationId = null;
    return value;
  }
}
