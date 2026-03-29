import 'package:flutter/widgets.dart';

import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';

/// Navigation / selection policy consumed only by the messaging workspace WM.
abstract class AppLayoutActions {
  const AppLayoutActions();

  void openRoom(BuildContext context, Chat chat);

  Future<void> openCreateChat(BuildContext context);

  void openSettings(BuildContext context);

  /// Desktop double-tap / pop-out; no-op on mobile.
  void openRoomInNewWindow(BuildContext context, Chat chat);
}

/// Single-pane stack: push [ConversationScreen].
final class CompactLayoutActions extends AppLayoutActions {
  CompactLayoutActions({
    required this.pushConversation,
    required this.pushCreate,
    required this.pushSettings,
    this.openRoomInNewWindowImpl,
  });

  final void Function(BuildContext context, Chat chat) pushConversation;
  final Future<String?> Function(BuildContext context) pushCreate;
  final void Function(BuildContext context) pushSettings;
  final void Function(BuildContext context, Chat chat)? openRoomInNewWindowImpl;

  @override
  void openRoom(BuildContext context, Chat chat) =>
      pushConversation(context, chat);

  @override
  Future<void> openCreateChat(BuildContext context) async {
    await pushCreate(context);
  }

  @override
  void openSettings(BuildContext context) => pushSettings(context);

  @override
  void openRoomInNewWindow(BuildContext context, Chat chat) {
    openRoomInNewWindowImpl?.call(context, chat);
  }
}

/// Split pane: update selection; no stack push for room open.
final class SplitLayoutActions extends AppLayoutActions {
  SplitLayoutActions({
    required this.onSelectRoom,
    required this.pushCreate,
    required this.pushSettings,
    required this.openRoomInNewWindowImpl,
  });

  final void Function(Chat chat) onSelectRoom;
  final Future<String?> Function(BuildContext context) pushCreate;
  final void Function(BuildContext context) pushSettings;
  final void Function(BuildContext context, Chat chat) openRoomInNewWindowImpl;

  @override
  void openRoom(BuildContext context, Chat chat) => onSelectRoom(chat);

  @override
  Future<void> openCreateChat(BuildContext context) async {
    await pushCreate(context);
  }

  @override
  void openSettings(BuildContext context) => pushSettings(context);

  @override
  void openRoomInNewWindow(BuildContext context, Chat chat) =>
      openRoomInNewWindowImpl(context, chat);
}
