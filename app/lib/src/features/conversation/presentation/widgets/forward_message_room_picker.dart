import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/features/conversation/presentation/widgets/forward_message_helpers.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix_sdk/matrix_sdk.dart' show Message;
import 'package:result_dart/result_dart.dart';

/// Pick a joined room (other than [sourceRoomId]) and send a forwarded plain-text message.
Future<void> showForwardMessageRoomPicker({
  required BuildContext context,
  required String sourceRoomId,
  required Message message,
  required Future<Result<String>> Function(String targetRoomId, String text)
      sendToRoom,
}) async {
  if (!context.mounted) return;
  final text = buildForwardedMessagePlainText(message);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: MatrixTheme.terminalBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      side: BorderSide(color: MatrixTheme.terminalBorder),
    ),
    builder: (ctx) {
      return _ForwardPickerBody(
        sourceRoomId: sourceRoomId,
        previewText: text,
        sendToRoom: sendToRoom,
      );
    },
  );
}

class _ForwardPickerBody extends StatefulWidget {
  const _ForwardPickerBody({
    required this.sourceRoomId,
    required this.previewText,
    required this.sendToRoom,
  });

  final String sourceRoomId;
  final String previewText;
  final Future<Result<String>> Function(String targetRoomId, String text)
      sendToRoom;

  @override
  State<_ForwardPickerBody> createState() => _ForwardPickerBodyState();
}

class _ForwardPickerBodyState extends State<_ForwardPickerBody> {
  final _search = TextEditingController();
  List<Chat> _rooms = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final raw = await MatrixService().client.getAllRooms();
      if (!mounted) return;
      final mapped = raw
          .map(
            (room) => Chat(
              id: room.roomId,
              name: room.displayName ?? room.rawName ?? room.roomId,
              lastMessage: '',
              lastActivity: null,
              isDirect: room.isDm ?? false,
              unreadCount: room.unreadMessages?.toInt() ?? 0,
              status: ChatRoomStatus.values.firstWhere(
                (s) => s.name == room.updateType.name,
              ),
              avatarUrl: room.avatarUrl,
              lastPreview: room.message,
            ),
          )
          .where(
            (c) =>
                c.id != widget.sourceRoomId &&
                c.status == ChatRoomStatus.joined &&
                !c.isArchivedForListing,
          )
          .toList();
      mapped.sort((a, b) {
        final na = a.name.toLowerCase();
        final nb = b.name.toLowerCase();
        return na.compareTo(nb);
      });
      setState(() {
        _rooms = mapped;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  List<Chat> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _rooms;
    return _rooms
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.id.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _send(Chat target) async {
    final nav = Navigator.of(context);
    final r = await widget.sendToRoom(target.id, widget.previewText);
    if (!mounted) return;
    r.fold(
      (_) {
        nav.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Forwarded to ${target.name}')),
        );
      },
      (f) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Forward failed: $f'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    return SafeArea(
      child: SizedBox(
        height: mq.size.height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                'Forward to…',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: MatrixTheme.fontFamily,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: 'Search rooms',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _filtered.isEmpty
                  ? Center(
                      child: Text(
                        _rooms.isEmpty
                            ? 'No other rooms to forward to'
                            : 'No matches',
                        style: theme.textTheme.bodyLarge,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (ctx, i) {
                        final c = _filtered[i];
                        return ListTile(
                          leading: Icon(
                            c.isDirect ? Icons.person : Icons.group,
                          ),
                          title: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            c.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          onTap: () => unawaited(_send(c)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
