import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/create_chat/create_room_screen.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/features/chat_lisitng/domain/services/chat_services.dart';
import 'package:matrix/src/features/chat_lisitng/presentation/screens/chat_listing_screen_wm.dart';
import 'package:matrix/src/features/chat_lisitng/routes/chat_listing_routes.dart';
import 'package:matrix/src/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:matrix/src/features/settings/presentation/screens/settings_screen.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

ChatListingScreenWM chatListingScreenWMFactory(BuildContext context) {
  return ChatListingScreenWM(ChatListingScreenModel(ChatServices()));
}

class ChatListingScreen extends ElementaryWidget<ChatListingScreenWM>
    implements ChatListingRoutes {
  const ChatListingScreen({super.key}) : super(chatListingScreenWMFactory);

  @override
  Widget build(ChatListingScreenWM wm) {
    return TerminalScreen(
      title: "MATRIX",
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: wm.createRoom,
          tooltip: 'Create Room',
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: wm.openSettings,
          tooltip: 'Settings',
        ),
      ],
      child: ListenableBuilder(
        listenable: wm.chatState,
        builder: (context, _) {
          final state = wm.chatState.value;
          return state.when(
            loading: () => loadingWidget(),
            loaded: (rooms) => _buildRoomsList(rooms, wm),
            error: (message) => errorWidget(message, wm),
          );
        },
      ),
    );
  }

  Center loadingWidget() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(MatrixTheme.matrixGreen),
          ),
          SizedBox(height: 16),
          Text('LOADING ROOMS...', style: MatrixTheme.statusStyle),
        ],
      ),
    );
  }

  Center errorWidget(String message, ChatListingScreenWM wm) {
    return Center(
      child: TerminalContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: MatrixTheme.errorRed,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'ERROR',
              style: MatrixTheme.titleStyle.copyWith(
                color: MatrixTheme.errorRed,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: MatrixTheme.bodyStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TerminalButton(
              text: 'RETRY',
              onPressed: wm.retry,
              icon: Icons.refresh,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomsList(List<Chat> rooms, ChatListingScreenWM wm) {
    if (rooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              color: MatrixTheme.matrixGreen,
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text('NO ROOMS FOUND', style: MatrixTheme.titleStyle),
            const SizedBox(height: 8),
            const Text(
              'Create or join a room to start chatting',
              style: MatrixTheme.bodyStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TerminalButton(
              text: 'START CHAT',
              onPressed: wm.createRoom,
              icon: Icons.message,
            ),
          ],
        ),
      );
    }

    return ValueListenableBuilder(
      valueListenable: wm.selectedChatType,
      builder: (context, selectedChatType, child) {
        final filteredRooms =
            rooms.where((element) {
              switch (selectedChatType) {
                case ChatType.all:
                  return true;
                case ChatType.invited:
                  return element.status == ChatRoomStatus.invited;
                case ChatType.direct:
                  return element.isDirect;
                case ChatType.group:
                  return !element.isDirect;
              }
            }).toList();

        return Column(
          children: [
            chatTypeGroupingWidget(wm, rooms),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filteredRooms.length,
                itemBuilder: (context, index) {
                  final room = filteredRooms[index];
                  return _buildRoomTile(
                    room,
                    context,
                    (chatId, roomName) => wm.navigateToConversationScreen(
                      context,
                      chatId,
                      roomName,
                      room.status,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRoomTile(
    Chat chat,
    BuildContext context,
    Function(String, String) goToConversation,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          goToConversation(chat.id, chat.name);
        },
        child: Row(
          children: [
            // Room avatar/icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: MatrixTheme.matrixGreen, width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                chat.isDirect ? Icons.person : Icons.group,
                color: MatrixTheme.matrixGreen,
                size: 20,
              ),
            ),

            const SizedBox(width: 16),

            // Room info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat.name,
                          style: MatrixTheme.bodyStyle.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    chat.lastMessage,
                    style: MatrixTheme.captionStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (chat.lastActivity != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                    child: Text(
                      chat.formatTime,
                      style: MatrixTheme.captionStyle,
                    ),
                  ),

                // Unread count
                Visibility(
                  visible: chat.unreadCount > 0,
                  maintainAnimation: true,
                  maintainState: true,
                  maintainSize: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: MatrixTheme.matrixGreen,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        chat.unreadCount.toString(),
                        textAlign: TextAlign.center,
                        style: MatrixTheme.captionStyle.copyWith(
                          color: MatrixTheme.terminalBlack,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget chatTypeGroupingWidget(ChatListingScreenWM wm, List<Chat> rooms) {
    return ValueListenableBuilder(
      valueListenable: wm.selectedChatType,
      builder: (context, selectedChatType, child) {
        String getCount(ChatType type) {
          switch (type) {
            case ChatType.all:
              return rooms.length.toString();
            case ChatType.invited:
              return rooms
                  .where((element) => element.status == ChatRoomStatus.invited)
                  .length
                  .toString();
            case ChatType.direct:
              return rooms
                  .where((element) => element.isDirect == true)
                  .length
                  .toString();
            case ChatType.group:
              return rooms
                  .where((element) => element.isDirect == false)
                  .length
                  .toString();
          }
        }

        return SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children:
                ChatType.values.map((type) {
                  return InkWell(
                    onTap: () {
                      wm.setSelectedChatType(type);
                    },
                    child: Container(
                      padding: EdgeInsets.all(10),
                      decoration:
                          type == selectedChatType
                              ? BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: MatrixTheme.primaryGreen,
                                    width: 2,
                                  ),
                                ),
                              )
                              : null,
                      child: Row(
                        children: [
                          Text(
                            type.name.toUpperCase(),
                            style: MatrixTheme.bodyStyle.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          Container(
                            height: 16,
                            width: 16,
                            alignment: Alignment.center,
                            margin: EdgeInsetsDirectional.only(start: 8),
                            decoration: BoxDecoration(
                              color: MatrixTheme.primaryGreen,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              getCount(type),
                              style: MatrixTheme.bodyStyle.copyWith(
                                color: MatrixTheme.darkBackground,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
          ),
        );
      },
    );
  }

  @override
  void navigateToConversationScreen(
    BuildContext context,
    String chatId,
    String roomName,
    ChatRoomStatus status,
  ) {
    NavigatorService.push(
      context,
      ConversationScreen(roomId: chatId, roomName: roomName, status: status),
    );
  }

  @override
  Future<String?> navigateToCreateScreen(BuildContext context) {
    return NavigatorService.push<String?>(context, const CreateRoomScreen());
  }

  @override
  void navigateToSettingsScreen(BuildContext context) {
    NavigatorService.push(context, const SettingsScreen());
  }
}
