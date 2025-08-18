import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/state_management/base_state_widget_model.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/features/chat_lisitng/domain/services/chat_services.dart';
import 'package:matrix/src/features/chat_lisitng/presentation/screens/chat_listing_screen.dart';
import 'package:matrix/src/core/logging_service.dart';

class ChatListingScreenModel extends ElementaryModel {
  ChatListingScreenModel(this._chatServices) : super();
  final ChatServices _chatServices;

  Future<List<Chat>> loadRooms() async {
    final result = await _chatServices.loadRooms();
    return result.fold(
      (success) =>
          success
              .map(
                (room) => Chat(
                  id: room.roomId,
                  name: room.displayName ?? room.rawName ?? '',
                  lastMessage: room.message?.content ?? '',
                  lastActivity:
                      (room.message?.timestamp ?? BigInt.from(0)) >
                              BigInt.from(0)
                          ? DateTime.fromMillisecondsSinceEpoch(
                            room.message!.timestamp.toInt(),
                          )
                          : null,
                  isDirect: room.isDm ?? false,
                  unreadCount: room.unreadMessages?.toInt() ?? 0,
                  status: ChatRoomStatus.values.firstWhere(
                    (status) => status.name == room.updateType.name,
                  ),
                ),
              )
              .toList(),
      (failure) {
        LoggingService.error(
          'CHAT_LISTING_SCREEN',
          'Failed to load rooms: $failure',
        );
        return [];
      },
    );
  }

  Stream<Chat> subscribeToAllRoomUpdates() {
    return _chatServices.subscribeToAllRoomUpdates().map((roomUpdate) {
      return Chat(
        id: roomUpdate.roomId,
        name: roomUpdate.displayName ?? roomUpdate.rawName ?? '',
        lastMessage: roomUpdate.message?.content ?? '',
        lastActivity:
            (roomUpdate.message?.timestamp ?? BigInt.from(0)) > BigInt.from(0)
                ? DateTime.fromMillisecondsSinceEpoch(
                  roomUpdate.message!.timestamp.toInt(),
                )
                : null,
        isDirect: roomUpdate.isDm ?? false,
        unreadCount: roomUpdate.unreadMessages?.toInt() ?? 0,
        status: ChatRoomStatus.values.firstWhere(
          (status) => status.name == roomUpdate.updateType.name,
        ),
      );
    });
  }
}

class ChatListingScreenWM
    extends BaseWidgetModel<ChatListingScreen, ChatListingScreenModel> {
  ChatListingScreenWM(super.model);
  final ValueNotifier<ChatState> _chatState = ValueNotifier(
    const ChatState.loading(),
  );

  ValueNotifier<ChatState> get chatState => _chatState;
  final ValueNotifier<ChatType> _selectedChatType = ValueNotifier(ChatType.all);

  ValueNotifier<ChatType> get selectedChatType => _selectedChatType;
  List<Chat> _rooms = [];

  @override
  void initWidgetModel() {
    super.initWidgetModel();
    _loadAllChats();
    _listenToChatUpdates();
  }

  @override
  void dispose() {
    _chatState.dispose();
    super.dispose();
  }

  Future<void> _loadAllChats() async {
    _chatState.value = const ChatState.loading();

    try {
      final rooms = await model.loadRooms();
      _rooms = rooms.toList();
      _chatState.value = ChatState.loaded(rooms: rooms);
    } catch (e) {
      _chatState.value = ChatState.error(message: 'Failed to load rooms: $e');
    }
  }

  void createRoom() {
    widget.navigateToCreateScreen(context);
  }

  void openSettings() {
    widget.navigateToSettingsScreen(context);
  }

  void _listenToChatUpdates() {
    model.subscribeToAllRoomUpdates().listen((updates) {
      LoggingService.info(
        'CHAT_LISTING_SCREEN',
        'Received chat update: $updates',
      );
      final int index = _rooms.indexWhere(
        (element) => element.id == updates.id,
      );
      switch (updates.status) {
        case ChatRoomStatus.joined:
          if (index == -1) {
            _rooms.add(updates);
          } else {
            _rooms[index] = updates;
          }
          break;
        case ChatRoomStatus.left:
          if (index != -1) {
            _rooms.removeAt(index);
          }
          break;
        case ChatRoomStatus.invited:
          if (index == -1) {
            _rooms.add(updates);
          } else {
            _rooms[index] = updates;
          }
          break;
        case ChatRoomStatus.knocked:
          _rooms.removeWhere((element) => element.id == updates.id);
          break;
        case ChatRoomStatus.banned:
          if (index == -1) {
            _rooms.add(updates);
          } else {
            _rooms[index] = updates;
          }
          break;
      }
      _chatState.value = ChatState.loaded(rooms: _rooms.toList());
      _selectedChatType.value = _selectedChatType.value;
    });
  }

  void retry() {
    _loadAllChats();
  }

  void navigateToConversationScreen(
    BuildContext context,
    String chatId,
    String roomName,
    ChatRoomStatus status,
  ) {
    widget.navigateToConversationScreen(context, chatId, roomName, status);
  }

  void setSelectedChatType(ChatType type) {
    _selectedChatType.value = type;
  }
}
