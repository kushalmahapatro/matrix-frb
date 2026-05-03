import 'package:flutter/material.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';

abstract class ChatListingRoutes {
  void navigateToConversationScreen(
    BuildContext context,
    String chatId,
    String roomName,
    ChatRoomStatus status,
  );

  void navigateToSettingsScreen(BuildContext context);

  Future<String?> navigateToCreateScreen(BuildContext context);
}
