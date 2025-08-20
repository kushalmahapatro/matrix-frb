import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';

import 'package:matrix/src/core/state_management/base_state_widget_model.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/features/conversation/domain/models/conversation_state.dart'
    hide MessageType;
import 'package:matrix/src/features/conversation/domain/services/conversation_service.dart';
import 'package:matrix/src/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:matrix/src/rust/matrix/timelines.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:result_dart/result_dart.dart';

class ConversationScreenModel extends ElementaryModel {
  ConversationScreenModel(this.conversationService) : super();
  final ConversationService conversationService;

  Future<Result<List<Message>>> loadMessages(String roomId) async {
    final messages = await conversationService.loadMessages(roomId);
    return messages;
  }

  Future<ConversationInfo> loadRoomInfo() async {
    final roomInfo = await conversationService.loadRoomInfo();
    return roomInfo;
  }

  Future<Result<String>> sendMessage(String roomId, String content) async {
    final result = await conversationService.sendMessage(roomId, content);
    return result;
  }

  Stream<MessageUpdate> subscribeToChatUpdates(String roomId) {
    return conversationService.subscribeToTimelineUpdates(roomId);
  }

  Future<Result<String>> acceptInvite(String roomId) {
    return conversationService.acceptInvite(roomId);
  }

  Future<Result<String>> rejectInvite(String roomId) {
    return conversationService.rejectInvite(roomId);
  }

  Future<Result<List<Message>>> fetchOlderMessages({
    required String conversationId,
    int count = 20,
  }) async {
    final messages = await conversationService.fetchOlderMessages(
      roomId: conversationId,
      count: count,
    );
    return messages;
  }
}

class ConversationScreenWM
    extends BaseWidgetModel<ConversationScreen, ConversationScreenModel> {
  ConversationScreenWM(super.model);
  final ValueNotifier<ConversationState> _roomState = ValueNotifier(
    const ConversationState.loading(),
  );

  final ValueNotifier<bool> _isInvited = ValueNotifier(false);
  late final TextEditingController _messageController;

  ValueNotifier<ConversationState> get roomState => _roomState;
  TextEditingController get messageController => _messageController;
  ValueNotifier<bool> get isInvited => _isInvited;

  @override
  void initWidgetModel() {
    super.initWidgetModel();
    _messageController = TextEditingController();

    if (widget.status == ChatRoomStatus.invited) {
      _roomState.value = const ConversationState.waitingForInvite();
      _isInvited.value = true;
    } else {
      _loadMessages();
    }
  }

  @override
  void dispose() {
    _roomState.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    _roomState.value = const ConversationState.loading();

    try {
      final messages = await model.loadMessages(widget.roomId);
      final roomInfo = await model.loadRoomInfo();

      messages.fold(
        (success) =>
            _roomState.value = ConversationState.loaded(
              messages: success.toList(),
              roomInfo: roomInfo,
            ),
        (failure) =>
            _roomState.value = ConversationState.error(
              message: 'Failed to load messages: $failure',
            ),
      );
    } catch (e) {
      _roomState.value = ConversationState.error(
        message: 'Failed to load messages: $e',
      );
    }
    _listenToChatUpdates();
  }

  Future<void> sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    try {
      final success = await model.sendMessage(widget.roomId, content);
      if (success.isSuccess()) {
        _messageController.clear();
      }
    } catch (e) {
      // Show error message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: MatrixTheme.errorRed,
          ),
        );
      }
    }
  }

  void showRoomInfo() {
    widget.showRoomInfo(context);
  }

  void retry() {
    _loadMessages();
  }

  void _listenToChatUpdates() {
    model.subscribeToChatUpdates(widget.roomId).listen((update) {
      final currentState = roomState.value;
      if (currentState is! RoomStateLoaded) {
        return;
      }
      switch (update.messageUpdateType) {
        case MessageUpdateType.append:
          if (update.messages != null) {
            _roomState.value = ConversationState.loaded(
              messages: [...currentState.messages, ...update.messages ?? []],
              roomInfo: currentState.roomInfo,
            );
          }
          break;
        case MessageUpdateType.pushFront:
          if (update.messages != null && update.messages!.length == 1) {
            _roomState.value = ConversationState.loaded(
              messages: [...update.messages ?? [], ...currentState.messages],
              roomInfo: currentState.roomInfo,
            );
          }
          break;
        case MessageUpdateType.remove:
          if (update.index != null &&
              update.index!.toInt() < currentState.messages.length &&
              update.index!.toInt() >= 0) {
            final newMessages = List<Message>.from(currentState.messages);
            newMessages.removeAt(update.index!.toInt());
            _roomState.value = ConversationState.loaded(
              messages: newMessages,
              roomInfo: currentState.roomInfo,
            );
          }
          break;
        case MessageUpdateType.reset:
          if (update.messages != null) {
            _roomState.value = ConversationState.loaded(
              messages: update.messages ?? [],
              roomInfo: currentState.roomInfo,
            );
          }
          break;
        case MessageUpdateType.truncate:
          if (update.index != null &&
              update.index!.toInt() < currentState.messages.length &&
              update.index!.toInt() >= 0) {
            final newMessages = List<Message>.from(currentState.messages);
            newMessages.removeRange(update.index!.toInt(), newMessages.length);
            _roomState.value = ConversationState.loaded(
              messages: newMessages,
              roomInfo: currentState.roomInfo,
            );
          }
          break;
        case MessageUpdateType.set_:
          if (update.index != null &&
              update.messages != null &&
              update.messages!.length == 1 &&
              update.index!.toInt() < currentState.messages.length &&
              update.index!.toInt() >= 0) {
            final newMessages = List<Message>.from(currentState.messages);
            newMessages[update.index!.toInt()] = update.messages!.first;
            _roomState.value = ConversationState.loaded(
              messages: newMessages,
              roomInfo: currentState.roomInfo,
            );
          }
          break;
        case MessageUpdateType.insert:
          if (update.index != null &&
              update.messages != null &&
              update.messages!.length == 1 &&
              update.index!.toInt() < currentState.messages.length &&
              update.index!.toInt() >= 0) {
            final newMessages = List<Message>.from(currentState.messages);
            newMessages.insert(update.index!.toInt(), update.messages!.first);
            _roomState.value = ConversationState.loaded(
              messages: newMessages,
              roomInfo: currentState.roomInfo,
            );
          }
          break;
        case MessageUpdateType.popBack:
          if (update.index != null &&
              update.messages != null &&
              update.messages!.length == 1) {
            final newMessages = List<Message>.from(currentState.messages);
            newMessages.removeLast();
            _roomState.value = ConversationState.loaded(
              messages: newMessages,
              roomInfo: currentState.roomInfo,
            );
          }
          break;
        case MessageUpdateType.popFront:
          if (update.messages != null && update.messages!.length == 1) {
            final newMessages = List<Message>.from(currentState.messages);
            newMessages.removeAt(0);
            _roomState.value = ConversationState.loaded(
              messages: newMessages,
              roomInfo: currentState.roomInfo,
            );
          }
          break;

        case MessageUpdateType.pushBack:
          if (update.messages != null && update.messages!.length == 1) {
            final newMessages = List<Message>.from(currentState.messages);
            newMessages.add(update.messages!.first);
            _roomState.value = ConversationState.loaded(
              messages: newMessages,
              roomInfo: currentState.roomInfo,
            );
          }
          break;

        case MessageUpdateType.clear:
          if (update.messages != null && update.messages!.length == 1) {
            final newMessages = List<Message>.from(currentState.messages);
            newMessages.clear();
            _roomState.value = ConversationState.loaded(
              messages: newMessages,
              roomInfo: currentState.roomInfo,
            );
          }
          break;
      }
    });
  }

  Future<void> acceptInvite() async {
    final result = await model.acceptInvite(widget.roomId);
    if (result.isSuccess()) {
      _isInvited.value = false;
      _loadMessages();
    }
  }

  Future<void> rejectInvite() async {
    final result = await model.rejectInvite(widget.roomId);
    if (result.isSuccess() && context.mounted) {
      widget.goBack(context);
    }
  }

  Future<List<Message>> fetchOlderMessages({
    required String conversationId,
    int limit = 20,
  }) async {
    final result = await model.fetchOlderMessages(
      conversationId: conversationId,
      count: limit,
    );

    return result.fold((success) => success, (failure) => []);
  }
}
