import 'dart:typed_data';

import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/features/chat_lisitng/presentation/screens/chat_listing_screen_wm.dart';
import 'package:matrix/src/features/chat_lisitng/routes/chat_listing_routes.dart';
import 'package:matrix/src/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:matrix/src/features/create_chat/presentation/screens/create_chat_screen.dart';
import 'package:matrix/src/features/settings/presentation/screens/settings_screen.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix_sdk/matrix_sdk.dart';
import 'package:path/path.dart' as p;

ChatListingScreenWM chatListingScreenWMFactory(BuildContext context) {
  return ChatListingScreenWM(ChatListingScreenModel(MatrixService()));
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
            loading: () => loadingWidget(context),
            loaded: (rooms) => _buildRoomsList(rooms, wm),
            error: (message) => errorWidget(message, wm, context),
          );
        },
      ),
    );
  }

  Widget loadingWidget(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text('LOADING ROOMS...', style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }

  Widget errorWidget(
    String message,
    ChatListingScreenWM wm,
    BuildContext context,
  ) {
    final theme = Theme.of(context);
    return Center(
      child: TerminalContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
            const SizedBox(height: 16),
            Text(
              'ERROR',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
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
      return Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  color: theme.colorScheme.primary,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text('NO ROOMS FOUND', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Create or join a room to start chatting',
                  style: theme.textTheme.bodyMedium,
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
        },
      );
    }

    return ValueListenableBuilder(
      valueListenable: wm.selectedChatType,
      builder: (context, selectedChatType, child) {
        final filteredRooms = rooms.where((element) {
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
                    wm,
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
    ChatListingScreenWM wm,
    Function(String, String) goToConversation,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => goToConversation(chat.id, chat.name),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: scheme.primary, width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                chat.isDirect ? Icons.person : Icons.group,
                color: scheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (chat.lastPreview != null &&
                      _chatListingShowsMediaRow(chat.lastPreview!))
                    _ChatListingMediaSubtitle(
                      roomId: chat.id,
                      message: chat.lastPreview!,
                      loadThumbnail: () => wm.loadListingThumbnail(
                        chat.id,
                        chat.lastPreview!,
                      ),
                      textStyle: theme.textTheme.bodySmall,
                    )
                  else
                    Text(
                      chat.lastMessage,
                      style: theme.textTheme.bodySmall,
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
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (chat.unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      chat.unreadCount.toString(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimary,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
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

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: ChatType.values.map((type) {
              return InkWell(
                onTap: () => wm.setSelectedChatType(type),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: type == selectedChatType
                      ? BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: scheme.primary, width: 2),
                          ),
                        )
                      : null,
                  child: Row(
                    children: [
                      Text(
                        type.name.toUpperCase(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        height: 16,
                        width: 16,
                        alignment: Alignment.center,
                        margin: const EdgeInsetsDirectional.only(start: 8),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          getCount(type),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onPrimary,
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
    return NavigatorService.push<String?>(context, const CreateChatScreen());
  }

  @override
  void navigateToSettingsScreen(BuildContext context) {
    NavigatorService.push(context, const SettingsScreen());
  }
}

bool _chatListingShowsMediaRow(Message m) {
  switch (m.roomMsgKind) {
    case RoomMessageKind.image:
    case RoomMessageKind.video:
    case RoomMessageKind.audio:
    case RoomMessageKind.file:
      return true;
    case RoomMessageKind.text:
    case RoomMessageKind.other:
      return false;
  }
}

String _chatListingExtLower(String label) {
  final base = p.basename(label.trim());
  final dot = base.lastIndexOf('.');
  if (dot < 0 || dot >= base.length - 1) return '';
  return base.substring(dot + 1).toLowerCase();
}

String _chatListingTypeLabel(Message m) {
  final mime = m.mediaMimetype.trim();
  if (mime.isNotEmpty) return mime;
  final ext = _chatListingExtLower(m.content);
  return switch (m.roomMsgKind) {
    RoomMessageKind.image => 'Image',
    RoomMessageKind.video => 'Video',
    RoomMessageKind.audio => 'Audio',
    RoomMessageKind.file => ext.isNotEmpty ? ext.toUpperCase() : 'File',
    _ => 'Attachment',
  };
}

IconData _chatListingKindIcon(RoomMessageKind k) {
  switch (k) {
    case RoomMessageKind.image:
      return Icons.image_outlined;
    case RoomMessageKind.video:
      return Icons.video_file_outlined;
    case RoomMessageKind.audio:
      return Icons.audio_file_outlined;
    case RoomMessageKind.file:
      return Icons.insert_drive_file_outlined;
    case RoomMessageKind.text:
    case RoomMessageKind.other:
      return Icons.attach_file_outlined;
  }
}

bool _chatListingRasterBytes(Uint8List data) {
  if (data.length < 12) return false;
  if (data.length >= 3 &&
      data[0] == 0xFF &&
      data[1] == 0xD8 &&
      data[2] == 0xFF) {
    return true;
  }
  if (data.length >= 8 &&
      data[0] == 0x89 &&
      data[1] == 0x50 &&
      data[2] == 0x4E &&
      data[3] == 0x47 &&
      data[4] == 0x0D &&
      data[5] == 0x0A &&
      data[6] == 0x1A &&
      data[7] == 0x0A) {
    return true;
  }
  if (data.length >= 6 &&
      data[0] == 0x47 &&
      data[1] == 0x49 &&
      data[2] == 0x46) {
    final g = String.fromCharCodes(data.sublist(0, 6));
    if (g == 'GIF87a' || g == 'GIF89a') return true;
  }
  if (data.length >= 12 &&
      data[0] == 0x52 &&
      data[1] == 0x49 &&
      data[2] == 0x46 &&
      data[3] == 0x46 &&
      data[8] == 0x57 &&
      data[9] == 0x45 &&
      data[10] == 0x42 &&
      data[11] == 0x50) {
    return true;
  }
  if (data.length >= 2 && data[0] == 0x42 && data[1] == 0x4D) return true;
  return false;
}

class _ChatListingMediaSubtitle extends StatefulWidget {
  const _ChatListingMediaSubtitle({
    required this.roomId,
    required this.message,
    required this.loadThumbnail,
    required this.textStyle,
  });

  final String roomId;
  final Message message;
  final Future<Uint8List?> Function() loadThumbnail;
  final TextStyle? textStyle;

  @override
  State<_ChatListingMediaSubtitle> createState() =>
      _ChatListingMediaSubtitleState();
}

class _ChatListingMediaSubtitleState extends State<_ChatListingMediaSubtitle> {
  static const double _thumb = 12;
  static const double _thumbRadius = 2;

  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.message.roomMsgKind == RoomMessageKind.audio) {
      _loading = false;
      return;
    }
    final id = widget.message.eventId.isNotEmpty
        ? widget.message.eventId
        : widget.message.transactionId;
    if (id.isEmpty) {
      _loading = false;
      return;
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant _ChatListingMediaSubtitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId ||
        oldWidget.message.eventId != widget.message.eventId ||
        oldWidget.message.transactionId != widget.message.transactionId ||
        oldWidget.message.roomMsgKind != widget.message.roomMsgKind) {
      if (widget.message.roomMsgKind == RoomMessageKind.audio) {
        setState(() {
          _loading = false;
          _bytes = null;
        });
        return;
      }
      final id = widget.message.eventId.isNotEmpty
          ? widget.message.eventId
          : widget.message.transactionId;
      if (id.isEmpty) {
        setState(() {
          _loading = false;
          _bytes = null;
        });
        return;
      }
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _bytes = null;
    });
    try {
      var b = await widget.loadThumbnail();
      if (b != null && b.isNotEmpty && !_chatListingRasterBytes(b)) {
        b = null;
      }
      if (!mounted) return;
      setState(() {
        _bytes = b;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bytes = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = _chatListingTypeLabel(widget.message);
    final icon = _chatListingKindIcon(widget.message.roomMsgKind);

    Widget thumb;
    if (_loading) {
      thumb = SizedBox(
        width: _thumb,
        height: _thumb,
        child: Center(
          child: SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: scheme.primary,
            ),
          ),
        ),
      );
    } else if (_bytes != null && _bytes!.isNotEmpty) {
      thumb = ClipRRect(
        borderRadius: BorderRadius.circular(_thumbRadius),
        child: Image.memory(
          _bytes!,
          width: _thumb,
          height: _thumb,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              Icon(icon, size: 10, color: scheme.primary),
        ),
      );
    } else {
      thumb = Container(
        width: _thumb,
        height: _thumb,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_thumbRadius),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
        ),
        child: Icon(icon, size: 10, color: scheme.primary),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        thumb,
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            style: widget.textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
