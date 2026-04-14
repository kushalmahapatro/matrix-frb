import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/muted_chats_store.dart';
import 'package:matrix/src/core/timeline_local_hidden_store.dart';
import 'package:matrix/src/core/timeline_raster_thumb.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/core/matrix_avatar_disk_cache.dart';
import 'package:matrix/src/core/presentation/widgets/typing_dots_indicator.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix_sdk/matrix_sdk.dart';
import 'package:path/path.dart' as p;

/// Same filter as [ChatListPane] — used to validate keyboard focus when the tab changes.
List<Chat> filteredChatsForListing(
  List<Chat> rooms,
  ChatType selectedChatType,
) {
  return rooms.where((element) {
    switch (selectedChatType) {
      case ChatType.all:
        return !element.isArchivedForListing;
      case ChatType.invited:
        return element.status == ChatRoomStatus.invited;
      case ChatType.direct:
        return element.isDirect && !element.isArchivedForListing;
      case ChatType.group:
        return !element.isDirect && !element.isArchivedForListing;
      case ChatType.left:
        return element.isArchivedForListing;
    }
  }).toList();
}

int _chatActivityCompareDesc(Chat a, Chat b) {
  final ta = a.lastActivity?.millisecondsSinceEpoch ?? 0;
  final tb = b.lastActivity?.millisecondsSinceEpoch ?? 0;
  return tb.compareTo(ta);
}

/// Invites first (for [ChatType.all]), then others; each block sorted by recent activity.
List<Chat> orderedChatsForListing(
  List<Chat> rooms,
  ChatType selectedChatType,
) {
  final filtered = filteredChatsForListing(rooms, selectedChatType);
  if (selectedChatType != ChatType.all) {
    filtered.sort(_chatActivityCompareDesc);
    return filtered;
  }
  final invites =
      filtered.where((c) => c.status == ChatRoomStatus.invited).toList();
  final rest =
      filtered.where((c) => c.status != ChatRoomStatus.invited).toList();
  invites.sort(_chatActivityCompareDesc);
  rest.sort(_chatActivityCompareDesc);
  return [...invites, ...rest];
}

List<Chat> filterChatsBySearchQuery(List<Chat> ordered, String query) {
  final t = query.trim().toLowerCase();
  if (t.isEmpty) return ordered;
  return ordered.where((c) {
    return c.name.toLowerCase().contains(t) ||
        c.lastMessage.toLowerCase().contains(t) ||
        c.id.toLowerCase().contains(t);
  }).toList();
}

/// One row in the room list: section title or a chat tile.
class ChatListRow {
  ChatListRow._({this.sectionTitle, this.chat})
    : assert(
        (sectionTitle != null) != (chat != null),
        'Exactly one of sectionTitle or chat',
      );

  factory ChatListRow.section(String title) =>
      ChatListRow._(sectionTitle: title);

  factory ChatListRow.chatTile(Chat c) => ChatListRow._(chat: c);

  final String? sectionTitle;
  final Chat? chat;
}

List<ChatListRow> chatListRowsForDisplay(
  List<Chat> orderedFiltered,
  ChatType selectedChatType,
) {
  final out = <ChatListRow>[];
  if (selectedChatType != ChatType.all) {
    for (final c in orderedFiltered) {
      out.add(ChatListRow.chatTile(c));
    }
    return out;
  }
  var i = 0;
  while (i < orderedFiltered.length &&
      orderedFiltered[i].status == ChatRoomStatus.invited) {
    if (i == 0) {
      out.add(ChatListRow.section('Room invites'));
    }
    out.add(ChatListRow.chatTile(orderedFiltered[i]));
    i++;
  }
  if (i < orderedFiltered.length) {
    if (i > 0) {
      out.add(ChatListRow.section('Chats'));
    }
    for (; i < orderedFiltered.length; i++) {
      out.add(ChatListRow.chatTile(orderedFiltered[i]));
    }
  }
  return out;
}

List<Chat> chatsOnlyFromRows(List<ChatListRow> rows) {
  return rows.where((r) => r.chat != null).map((r) => r.chat!).toList();
}

KeyEventResult _handleRoomListKeyNavigation({
  required KeyEvent event,
  required List<Chat> filtered,
  required ValueNotifier<String?> keyboardFocusedRoomId,
  required ValueChanged<Chat> onActivateFocusedRoom,
}) {
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  if (filtered.isEmpty) return KeyEventResult.ignored;

  final key = event.logicalKey;
  if (key != LogicalKeyboardKey.arrowDown &&
      key != LogicalKeyboardKey.arrowUp &&
      key != LogicalKeyboardKey.space &&
      key != LogicalKeyboardKey.enter) {
    return KeyEventResult.ignored;
  }

  var idx = -1;
  final currentId = keyboardFocusedRoomId.value;
  if (currentId != null) {
    idx = filtered.indexWhere((c) => c.id == currentId);
  }

  if (key == LogicalKeyboardKey.arrowDown) {
    if (idx < 0) {
      keyboardFocusedRoomId.value = filtered.first.id;
    } else if (idx < filtered.length - 1) {
      keyboardFocusedRoomId.value = filtered[idx + 1].id;
    }
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    if (idx < 0) {
      keyboardFocusedRoomId.value = filtered.last.id;
    } else if (idx > 0) {
      keyboardFocusedRoomId.value = filtered[idx - 1].id;
    }
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) {
    if (idx >= 0 && idx < filtered.length) {
      onActivateFocusedRoom(filtered[idx]);
    }
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

/// Thin room list: data + intent callbacks only.
class ChatListPane extends StatelessWidget {
  const ChatListPane({
    super.key,
    required this.rooms,
    required this.selectedChatType,
    required this.onChatTypeSelected,
    required this.onRoomTap,
    required this.onRoomDoubleTap,
    required this.loadListingThumbnail,
    required this.loadRoomAvatarThumbnail,
    required this.onStartChatPressed,
    this.selectedRoomId,

    /// Desktop: right-click → context menu at [Offset] (global).
    this.onRoomSecondaryPointer,

    /// Desktop: middle-click (e.g. open in new window).
    this.onRoomMiddleClick,

    /// Desktop: arrow keys / space — separate from [selectedRoomId] highlight.
    this.listFocusNode,
    this.keyboardFocusedRoomId,
    this.typingByRoomId = const {},
    this.onRoomLongPress,
    this.searchQuery = '',
  });

  final List<Chat> rooms;

  /// Typing user ids per room id (from [MatrixService.roomListTypingUserIds]).
  final Map<String, List<String>> typingByRoomId;

  /// Room open in split pane / last selected (for highlight).
  final String? selectedRoomId;
  /// Filters [orderedChatsForListing] by name, last preview line, or room id.
  final String searchQuery;
  final ChatType selectedChatType;
  final ValueChanged<ChatType> onChatTypeSelected;
  final ValueChanged<Chat> onRoomTap;
  final ValueChanged<Chat> onRoomDoubleTap;
  final Future<Uint8List?> Function(String roomId, Message message)
  loadListingThumbnail;
  final Future<Uint8List?> Function(String mxcUri) loadRoomAvatarThumbnail;
  final VoidCallback onStartChatPressed;
  final void Function(Chat chat, Offset globalPosition)? onRoomSecondaryPointer;
  final ValueChanged<Chat>? onRoomMiddleClick;
  final FocusNode? listFocusNode;
  final ValueNotifier<String?>? keyboardFocusedRoomId;

  /// Mobile / touch: long-press on a row (e.g. mute / room options).
  final ValueChanged<Chat>? onRoomLongPress;

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) {
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
              onPressed: onStartChatPressed,
              icon: Icons.message,
            ),
          ],
        ),
      );
    }

    final ordered = orderedChatsForListing(rooms, selectedChatType);
    final filteredRooms = filterChatsBySearchQuery(ordered, searchQuery);
    final rows = chatListRowsForDisplay(filteredRooms, selectedChatType);

    final listPadding = isDesktopTargetPlatform()
        ? const EdgeInsets.fromLTRB(8, 6, 8, 10)
        : const EdgeInsets.all(16);

    return Column(
      children: [
        ChatListFilterBar(
          rooms: rooms,
          selectedChatType: selectedChatType,
          onChatTypeSelected: onChatTypeSelected,
        ),
        Expanded(
          child: _buildRoomListScrollable(
            context: context,
            listPadding: listPadding,
            rows: rows,
            keyboardChats: chatsOnlyFromRows(rows),
            typingByRoomId: typingByRoomId,
          ),
        ),
      ],
    );
  }

  Widget _buildRoomListScrollable({
    required BuildContext context,
    required EdgeInsets listPadding,
    required List<ChatListRow> rows,
    required List<Chat> keyboardChats,
    required Map<String, List<String>> typingByRoomId,
  }) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: MutedChatsStore.instance.ids,
      builder: (context, mutedIds, _) {
        Widget listForFocus(String? keyboardFocusId) {
          return ListView.builder(
            padding: listPadding,
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              if (row.sectionTitle != null) {
                final theme = Theme.of(context);
                final scheme = theme.colorScheme;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.mail_outline,
                          size: 18,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            row.sectionTitle!.toUpperCase(),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final room = row.chat!;
              final muted = mutedIds.contains(room.id);
              return ChatListRoomTile(
                chat: room,
                displayUnreadCount: muted ? 0 : room.unreadCount,
                isChatMuted: muted,
                typingUserIds: typingByRoomId[room.id] ?? const [],
                isSelected: selectedRoomId != null && room.id == selectedRoomId,
                isKeyboardFocused:
                    keyboardFocusId != null && room.id == keyboardFocusId,
                loadListingThumbnail: loadListingThumbnail,
                loadRoomAvatarThumbnail: loadRoomAvatarThumbnail,
                onTap: () => onRoomTap(room),
                onDoubleTap: () => onRoomDoubleTap(room),
                onSecondaryPointer: onRoomSecondaryPointer != null
                    ? (pos) => onRoomSecondaryPointer!(room, pos)
                    : null,
                onMiddleClick: onRoomMiddleClick != null
                    ? () => onRoomMiddleClick!(room)
                    : null,
                onLongPress: onRoomLongPress != null
                    ? () => onRoomLongPress!(room)
                    : null,
              );
            },
          );
        }

        final node = listFocusNode;
        final knob = keyboardFocusedRoomId;
        if (isDesktopTargetPlatform() && node != null && knob != null) {
          return Focus(
            focusNode: node,
            onKeyEvent: (n, event) => _handleRoomListKeyNavigation(
              event: event,
              filtered: keyboardChats,
              keyboardFocusedRoomId: knob,
              onActivateFocusedRoom: onRoomTap,
            ),
            child: ValueListenableBuilder<String?>(
              valueListenable: knob,
              builder: (context, focusId, _) => listForFocus(focusId),
            ),
          );
        }

        return listForFocus(null);
      },
    );
  }
}

class ChatListFilterBar extends StatelessWidget {
  const ChatListFilterBar({
    super.key,
    required this.rooms,
    required this.selectedChatType,
    required this.onChatTypeSelected,
  });

  final List<Chat> rooms;
  final ChatType selectedChatType;
  final ValueChanged<ChatType> onChatTypeSelected;

  @override
  Widget build(BuildContext context) {
    String getCount(ChatType type) {
      switch (type) {
        case ChatType.all:
          return rooms.where((r) => !r.isArchivedForListing).length.toString();
        case ChatType.invited:
          return rooms
              .where((element) => element.status == ChatRoomStatus.invited)
              .length
              .toString();
        case ChatType.direct:
          return rooms
              .where(
                (element) => element.isDirect && !element.isArchivedForListing,
              )
              .length
              .toString();
        case ChatType.group:
          return rooms
              .where(
                (element) => !element.isDirect && !element.isArchivedForListing,
              )
              .length
              .toString();
        case ChatType.left:
          return rooms.where((r) => r.isArchivedForListing).length.toString();
      }
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final desktop = isDesktopTargetPlatform();
    return SizedBox(
      height: desktop ? 40 : 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: desktop ? 4 : 8),
        children: ChatType.values.map((type) {
          final selected = type == selectedChatType;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onChatTypeSelected(type),
                borderRadius: BorderRadius.circular(4),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: selected
                          ? MatrixTheme.matrixAccent.withValues(alpha: 0.85)
                          : MatrixTheme.matrixGreen.withValues(alpha: 0.28),
                      width: selected ? 1.5 : 1,
                    ),
                    color: selected
                        ? MatrixTheme.matrixGreen.withValues(alpha: 0.12)
                        : MatrixTheme.terminalBlack.withValues(alpha: 0.25),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: MatrixTheme.matrixGreen.withValues(
                                alpha: 0.2,
                              ),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Text(
                        type.name.toUpperCase(),
                        style: MatrixTheme.labelStyle.copyWith(
                          fontSize: 11,
                          letterSpacing: 0.8,
                          color: selected
                              ? MatrixTheme.matrixLightGreen
                              : scheme.onSurface.withValues(alpha: 0.78),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        height: 18,
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? MatrixTheme.matrixAccent.withValues(alpha: 0.35)
                              : scheme.primary.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: MatrixTheme.matrixGreen.withValues(
                              alpha: selected ? 0.5 : 0.25,
                            ),
                          ),
                        ),
                        child: Text(
                          getCount(type),
                          style: MatrixTheme.captionStyle.copyWith(
                            color: MatrixTheme.terminalBlack,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ChatListRoomLeadingAvatar extends StatefulWidget {
  const _ChatListRoomLeadingAvatar({
    required this.chat,
    required this.scheme,
    required this.isInvited,
    required this.loadRoomAvatarThumbnail,
  });

  final Chat chat;
  final ColorScheme scheme;
  final bool isInvited;
  final Future<Uint8List?> Function(String mxcUri) loadRoomAvatarThumbnail;

  @override
  State<_ChatListRoomLeadingAvatar> createState() =>
      _ChatListRoomLeadingAvatarState();
}

class _ChatListRoomLeadingAvatarState extends State<_ChatListRoomLeadingAvatar> {
  Uint8List? _bytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_maybeLoad());
  }

  @override
  void didUpdateWidget(covariant _ChatListRoomLeadingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chat.avatarUrl != widget.chat.avatarUrl ||
        oldWidget.chat.isDirect != widget.chat.isDirect) {
      _bytes = null;
      unawaited(_maybeLoad());
    }
  }

  Future<void> _maybeLoad() async {
    final mxc = widget.chat.avatarUrl?.trim() ?? '';
    if (widget.chat.isDirect || mxc.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (_loading) return;
    if (mounted) setState(() => _loading = true);
    final b = await MatrixAvatarDiskCache.instance.loadOrFetch(
      mxc,
      () async {
        final x = await widget.loadRoomAvatarThumbnail(mxc);
        return x ?? Uint8List(0);
      },
    );
    if (!mounted) return;
    setState(() {
      _bytes = b;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    final isInvited = widget.isInvited;
    final mxc = widget.chat.avatarUrl?.trim() ?? '';
    final usePhoto = !widget.chat.isDirect &&
        mxc.isNotEmpty &&
        _bytes != null &&
        _bytes!.isNotEmpty;

    final border = BoxDecoration(
      border: Border.all(
        color: scheme.primary,
        width: isInvited ? 2 : 1,
      ),
      borderRadius: BorderRadius.circular(4),
    );

    if (usePhoto) {
      return Container(
        width: 40,
        height: 40,
        decoration: border,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Image.memory(
            _bytes!,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
      );
    }

    return Container(
      width: 40,
      height: 40,
      decoration: border,
      child: _loading && mxc.isNotEmpty && !widget.chat.isDirect
          ? Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: scheme.primary,
                ),
              ),
            )
          : Icon(
              widget.chat.isDirect ? Icons.person : Icons.group,
              color: scheme.primary,
              size: 20,
            ),
    );
  }
}

class ChatListRoomTile extends StatelessWidget {
  const ChatListRoomTile({
    super.key,
    required this.chat,
    required this.displayUnreadCount,
    this.isChatMuted = false,
    this.typingUserIds = const [],
    required this.isSelected,
    this.isKeyboardFocused = false,
    required this.loadListingThumbnail,
    required this.loadRoomAvatarThumbnail,
    required this.onTap,
    required this.onDoubleTap,
    this.onSecondaryPointer,
    this.onMiddleClick,
    this.onLongPress,
  });

  final Chat chat;
  /// May be zero when the room is muted even if [Chat.unreadCount] from sync is non-zero.
  final int displayUnreadCount;
  final bool isChatMuted;
  final List<String> typingUserIds;
  final bool isSelected;

  /// Keyboard row highlight (desktop); distinct from [isSelected].
  final bool isKeyboardFocused;
  final Future<Uint8List?> Function(String roomId, Message message)
  loadListingThumbnail;
  final Future<Uint8List?> Function(String mxcUri) loadRoomAvatarThumbnail;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset>? onSecondaryPointer;
  final VoidCallback? onMiddleClick;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isInvited = chat.status == ChatRoomStatus.invited;
    final selectedBg = scheme.primary.withValues(alpha: 0.18);
    final selectedBorder = scheme.primary.withValues(alpha: 0.85);
    final keyFocusColor = scheme.tertiary;
    final desktopPointers = onSecondaryPointer != null || onMiddleClick != null;

    final BoxDecoration? innerDecoration = isInvited
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: scheme.primary, width: 2),
            color: scheme.primary.withValues(alpha: 0.12),
          )
        : isSelected
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selectedBorder, width: 1.5),
            color: selectedBg,
          )
        : null;

    final bool padInner = isInvited || isSelected;
    final bool showKeyRing = isKeyboardFocused && !isInvited;

    Widget row = Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: showKeyRing
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: keyFocusColor, width: 2),
            )
          : null,
      padding: showKeyRing ? const EdgeInsets.all(2) : EdgeInsets.zero,
      child: Container(
        decoration: innerDecoration,
        padding: padInner ? const EdgeInsets.all(10) : EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          onLongPress: onLongPress,
          child: Row(
            children: [
              _ChatListRoomLeadingAvatar(
                chat: chat,
                scheme: scheme,
                isInvited: isInvited,
                loadRoomAvatarThumbnail: loadRoomAvatarThumbnail,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            chat.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isInvited) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(
                                color: scheme.primary.withValues(alpha: 0.85),
                              ),
                              color: scheme.primary.withValues(alpha: 0.2),
                            ),
                            child: Text(
                              'INVITED',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ] else if (isChatMuted) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 16,
                            color: scheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (typingUserIds.isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          TypingDotsIndicator(
                            color: scheme.primary.withValues(alpha: 0.88),
                            dotSize: 4,
                            spacing: 3,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              typingUserIdsShortLabel(typingUserIds),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: scheme.primary.withValues(alpha: 0.9),
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ] else if (chat.lastPreview != null &&
                        chat.lastPreview!.isRedacted)
                      ChatListingDeletedSubtitle(
                        textStyle: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                        ),
                      )
                    else if (chat.lastPreview != null &&
                        TimelineLocalHiddenStore.isHidden(chat.lastPreview!))
                      ChatListingRemovedOnDeviceSubtitle(
                        textStyle: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                        ),
                      )
                    else if (chat.lastPreview != null &&
                        chat.lastPreview!.roomMsgKind == RoomMessageKind.poll)
                      ChatListingPollSubtitle(
                        message: chat.lastPreview!,
                        textStyle: theme.textTheme.bodySmall,
                      )
                    else if (chat.lastPreview != null &&
                        _chatListingShowsMediaRow(chat.lastPreview!))
                      ChatListingMediaSubtitle(
                        roomId: chat.id,
                        message: chat.lastPreview!,
                        loadThumbnail: () =>
                            loadListingThumbnail(chat.id, chat.lastPreview!),
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
                  if (displayUnreadCount > 0)
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
                        displayUnreadCount.toString(),
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
      ),
    );

    if (desktopPointers) {
      row = Listener(
        behavior: HitTestBehavior.deferToChild,
        onPointerDown: (PointerDownEvent e) {
          if (e.kind != PointerDeviceKind.mouse) return;
          final box = context.findRenderObject() as RenderBox?;
          final global = box?.localToGlobal(e.localPosition) ?? e.localPosition;
          if (e.buttons == kSecondaryMouseButton) {
            onSecondaryPointer?.call(global);
          } else if (e.buttons == kMiddleMouseButton) {
            onMiddleClick?.call();
          }
        },
        child: row,
      );
    }

    if (isDesktopTargetPlatform() && chat.name.trim().isNotEmpty) {
      row = Tooltip(
        message: chat.name,
        waitDuration: const Duration(milliseconds: 450),
        child: row,
      );
    }

    return row;
  }
}

class ChatListingDeletedSubtitle extends StatelessWidget {
  const ChatListingDeletedSubtitle({super.key, required this.textStyle});

  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.remove_circle_outline, size: 13, color: c),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Message deleted',
            style: textStyle?.copyWith(fontStyle: FontStyle.italic, color: c),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class ChatListingRemovedOnDeviceSubtitle extends StatelessWidget {
  const ChatListingRemovedOnDeviceSubtitle({
    super.key,
    required this.textStyle,
  });

  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.visibility_off_outlined, size: 13, color: c),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Message removed on this device',
            style: textStyle?.copyWith(fontStyle: FontStyle.italic, color: c),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

bool _chatListingShowsMediaRow(Message m) {
  if (m.isRedacted) return false;
  if (TimelineLocalHiddenStore.isHidden(m)) return false;
  switch (m.roomMsgKind) {
    case RoomMessageKind.image:
    case RoomMessageKind.video:
    case RoomMessageKind.audio:
    case RoomMessageKind.file:
      return true;
    case RoomMessageKind.text:
    case RoomMessageKind.poll:
    case RoomMessageKind.call:
    case RoomMessageKind.other:
      return false;
  }
}

class ChatListingPollSubtitle extends StatelessWidget {
  const ChatListingPollSubtitle({
    super.key,
    required this.message,
    required this.textStyle,
  });

  final Message message;
  final TextStyle? textStyle;

  static const double _thumb = 12;
  static const double _thumbRadius = 2;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = message.content.trim().isEmpty ? 'Poll' : message.content;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: _thumb,
          height: _thumb,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_thumbRadius),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
          ),
          child: Icon(Icons.poll_outlined, size: 10, color: scheme.primary),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.45)),
          ),
          child: Text(
            'POLL',
            style: (textStyle ?? const TextStyle()).copyWith(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: scheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            preview,
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
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
    RoomMessageKind.poll => 'Poll',
    RoomMessageKind.call => 'Call',
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
    case RoomMessageKind.poll:
      return Icons.poll_outlined;
    case RoomMessageKind.call:
      return Icons.call_outlined;
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

class ChatListingMediaSubtitle extends StatefulWidget {
  const ChatListingMediaSubtitle({
    super.key,
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
  State<ChatListingMediaSubtitle> createState() =>
      _ChatListingMediaSubtitleState();
}

class _ChatListingMediaSubtitleState extends State<ChatListingMediaSubtitle> {
  static const double _thumb = 12;
  static const double _thumbRadius = 2;

  Uint8List? _bytes;
  bool _loading = true;

  bool get _canUseSubtitleBlurhash {
    final bh = widget.message.mediaBlurhash.trim();
    if (bh.isEmpty) return false;
    final k = widget.message.roomMsgKind;
    return k == RoomMessageKind.image ||
        k == RoomMessageKind.video ||
        k == RoomMessageKind.file;
  }

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
  void didUpdateWidget(covariant ChatListingMediaSubtitle oldWidget) {
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
      if (b != null && b.isNotEmpty) {
        final e = timelineThumbDecodeExtentPx(_thumb);
        final small = await encodeRasterPngFitBox(
          b,
          targetWidthPx: e,
          targetHeightPx: e,
        );
        if (small != null) b = small;
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
    final bh = widget.message.mediaBlurhash.trim();
    if (_loading) {
      thumb = SizedBox(
        width: _thumb,
        height: _thumb,
        child: _canUseSubtitleBlurhash
            ? ClipRRect(
                borderRadius: BorderRadius.circular(_thumbRadius),
                child: BlurHash(hash: bh, imageFit: BoxFit.cover),
              )
            : Center(
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
      final thumbDecode = timelineThumbImageDecodeCacheParams(
        logicalWidth: _thumb,
        logicalHeight: _thumb,
        context: context,
      );
      thumb = ClipRRect(
        borderRadius: BorderRadius.circular(_thumbRadius),
        child: Image.memory(
          _bytes!,
          width: _thumb,
          height: _thumb,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: thumbDecode.cacheWidth,
          cacheHeight: thumbDecode.cacheHeight,
          errorBuilder: (_, __, ___) => _canUseSubtitleBlurhash
              ? BlurHash(hash: bh, imageFit: BoxFit.cover)
              : Icon(icon, size: 10, color: scheme.primary),
        ),
      );
    } else if (_canUseSubtitleBlurhash) {
      thumb = ClipRRect(
        borderRadius: BorderRadius.circular(_thumbRadius),
        child: SizedBox(
          width: _thumb,
          height: _thumb,
          child: BlurHash(hash: bh, imageFit: BoxFit.cover),
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
