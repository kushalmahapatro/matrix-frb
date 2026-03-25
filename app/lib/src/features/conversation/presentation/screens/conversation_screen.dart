import 'dart:typed_data';

import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/timeline_local_hidden_store.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/features/conversation/domain/models/conversation_state.dart'
    hide MessageType;
import 'package:matrix/src/features/conversation/domain/services/conversation_service.dart';
import 'package:matrix/src/features/conversation/presentation/screens/conversation_screen_wm.dart';
import 'package:matrix/src/features/conversation/presentation/widgets/pagianted_message_list.dart';
import 'package:matrix/src/features/conversation/routes/conversation_routes.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix_sdk/matrix_sdk.dart'
    show FileSendPhase, FileSendProgress, Message, RoomMessageKind;

ConversationScreenWM conversationScreenWMFactory(BuildContext context) {
  return ConversationScreenWM(
    ConversationScreenModel(
      ConversationService(matrixService: MatrixService()),
    ),
  );
}

class ConversationScreen extends ElementaryWidget<ConversationScreenWM>
    implements ConversationRoutes {
  const ConversationScreen({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.status,
  }) : super(conversationScreenWMFactory);

  final String roomId;
  final String roomName;
  final ChatRoomStatus status;

  @override
  Widget build(ConversationScreenWM wm) {
    return TerminalScreen(
      title: roomName.toUpperCase(),
      actions: [
        ValueListenableBuilder<ConversationState>(
          valueListenable: wm.roomState,
          builder: (context, state, _) {
            final showPoll = state.maybeWhen(
              loaded: (_, ri) => !ri.isDirect,
              orElse: () => false,
            );
            if (!showPoll) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.poll_outlined),
              onPressed: wm.showCreatePollDialog,
              tooltip: 'Poll',
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.info_outline),
          onPressed: wm.showRoomInfo,
          tooltip: 'Room Info',
        ),
      ],
      child: Column(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: wm.showPendingOutgoingInvite,
            builder: (context, pending, _) {
              if (!pending) return const SizedBox.shrink();
              return _pendingOutgoingInviteBanner(context);
            },
          ),
          // Messages list
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                wm.roomState,
                TimelineLocalHiddenStore.revision,
              ]),
              builder: (context, child) {
                final state = wm.roomState.value;
                final theme = Theme.of(context);
                return state.when(
                  waitingForInvite: () => Center(
                    child: Text(
                      'WAITING FOR INVITE TO BE ACCEPTED...',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  loading: () => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'LOADING MESSAGES...',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  loaded: (messages, roomInfo) {
                    return PaginatedMessageList(
                      roomId: roomId,
                      loadMessageMedia: wm.fetchRoomMessageMedia,
                      onOpenAttachment: wm.openAttachment,
                      initialMessages: messages,
                      loadOlder: (Message oldest) async {
                        return await wm.fetchOlderMessages(
                          conversationId: roomId,
                          limit: 50,
                        );
                      },
                      onRetryFailedSend: wm.retryFailedSend,
                      onVisibleRange:
                          (Message firstVisible, Message lastVisible) {},
                      jumpToEventNotifier: wm.jumpToTimelineEventId,
                      isGroupRoom: !roomInfo.isDirect,
                      onToggleReaction: wm.toggleTimelineReaction,
                      onShowReactionReactors: wm.showReactionReactorsSheet,
                      onPollVote: wm.voteOnPoll,
                      onShowMessageActions: wm.showMessageActionsMenu,
                    );
                  },
                  error: (errMessage) => Center(
                    child: TerminalContainer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: theme.colorScheme.error,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'ERROR',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            errMessage,
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
                  ),
                );
              },
            ),
          ),

          // Message input
          ValueListenableBuilder<bool>(
            valueListenable: wm.isInvited,
            builder: (context, isInvited, child) {
              if (isInvited) {
                return _acceptInviteWidget(wm);
              } else {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ValueListenableBuilder<FileSendProgress?>(
                      valueListenable: wm.fileSendProgress,
                      builder: (context, prog, _) {
                        if (prog == null) return const SizedBox.shrink();
                        return _fileSendProgressBanner(context, wm, prog);
                      },
                    ),
                    ValueListenableBuilder<Message?>(
                      valueListenable: wm.replyDraft,
                      builder: (context, draft, _) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (draft != null)
                              _replyDraftBanner(context, wm, draft),
                            _buildMessageInput(context, wm),
                          ],
                        );
                      },
                    ),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _pendingOutgoingInviteBanner(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.55)),
          color: scheme.primary.withValues(alpha: 0.1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.hourglass_top_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INVITATION PENDING',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'The other person has not accepted the invite yet. '
                      'This notice disappears when they join the room.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fileSendProgressBanner(
    BuildContext context,
    ConversationScreenWM wm,
    FileSendProgress prog,
  ) {
    final theme = Theme.of(context);
    final ratio = _fileSendProgressRatio(prog);
    final bytesLabel = _fileSendBytesLabel(prog);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _fileSendPhaseLabel(prog.phase),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: wm.cancelFileSend,
                    child: const Text('CANCEL'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: ratio),
              const SizedBox(height: 8),
              Text(
                bytesLabel,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fileSendPhaseLabel(FileSendPhase phase) {
    switch (phase) {
      case FileSendPhase.videoCompress:
        return 'COMPRESSING VIDEO';
      case FileSendPhase.mainUpload:
        return 'UPLOADING FILE';
      case FileSendPhase.thumbnailUpload:
        return 'UPLOADING THUMBNAIL';
      case FileSendPhase.sendingMessage:
        return 'SENDING MESSAGE';
      case FileSendPhase.encryptedQueued:
        return 'ENCRYPTED SEND (QUEUE)';
      case FileSendPhase.done:
        return 'DONE';
      case FileSendPhase.cancelled:
        return 'CANCELLED';
      case FileSendPhase.failed:
        return 'FAILED';
    }
  }

  /// Determinate bar when `total > 0`; otherwise indeterminate (`null`).
  /// Encrypted send-queue path has no live byte counter — keep bar indeterminate.
  double? _fileSendProgressRatio(FileSendProgress p) {
    if (p.phase == FileSendPhase.encryptedQueued) return null;
    final t = p.total;
    if (t <= BigInt.zero) return null;
    final scaled = (p.current * BigInt.from(10_000)) ~/ t;
    return scaled.toInt().clamp(0, 10_000) / 10_000.0;
  }

  String _fileSendBytesLabel(FileSendProgress p) {
    if (p.phase == FileSendPhase.encryptedQueued) {
      if (p.total <= BigInt.zero) {
        return 'Encrypting and uploading…';
      }
      return '${p.current} / ${p.total} bytes (encrypted — no live upload counter)';
    }
    if (p.total <= BigInt.zero) {
      return 'Working…';
    }
    return '${p.current} / ${p.total} bytes';
  }

  /// Text-only preview for non-media replies (never shows attachment filenames here).
  String _replyDraftTextPreview(Message m) {
    if (m.isRedacted) return 'Deleted message';
    if (TimelineLocalHiddenStore.isHidden(m)) {
      return 'Message removed on this device';
    }
    final raw = m.content.trim();
    if (raw.isNotEmpty) {
      return raw.length > 72 ? '${raw.substring(0, 69)}…' : raw;
    }
    return 'Message';
  }

  bool _replyDraftIsMediaMessage(Message m) {
    final lookup = m.eventId.isNotEmpty ? m.eventId : m.transactionId;
    if (lookup.isEmpty) return false;
    return switch (m.roomMsgKind) {
      RoomMessageKind.image => true,
      RoomMessageKind.video => true,
      RoomMessageKind.audio => true,
      RoomMessageKind.file => true,
      RoomMessageKind.text => false,
      RoomMessageKind.poll => false,
      RoomMessageKind.other => false,
    };
  }

  String? _replyDraftMediaMetaLine(Message m) {
    final parts = <String>[];
    final mime = m.mediaMimetype.trim();
    if (mime.isNotEmpty) parts.add(mime);
    final sz = _replyDraftFormatBytes(m.mediaSizeBytes);
    if (sz != null) parts.add(sz);
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  String? _replyDraftFormatBytes(BigInt bytes) {
    if (bytes <= BigInt.zero) return null;
    double v;
    try {
      v = bytes.toDouble();
    } catch (_) {
      return '${bytes.toString()} B';
    }
    if (!v.isFinite || v <= 0) return null;
    if (v < 1024) return '${bytes.toString()} B';
    if (v < 1024 * 1024) {
      final kb = v / 1024;
      return '${kb >= 100 ? kb.toStringAsFixed(0) : kb.toStringAsFixed(1)} KB';
    }
    final mb = v / (1024 * 1024);
    return '${mb >= 10 ? mb.toStringAsFixed(1) : mb.toStringAsFixed(2)} MB';
  }

  Widget _replyDraftBanner(
    BuildContext context,
    ConversationScreenWM wm,
    Message draft,
  ) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final isMedia = _replyDraftIsMediaMessage(draft);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          // Accent on the “your side” (end) to mirror incoming bubbles’ start bar.
          border: BorderDirectional(
            start: BorderSide.none,
            end: BorderSide(color: accent, width: 3),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 10, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Cancel reply',
                onPressed: wm.clearReplyDraft,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '> REPLY TO ${draft.displayName}',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (isMedia)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final meta = _replyDraftMediaMetaLine(draft);
                                if (meta == null) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  meta,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.72),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          _ReplyDraftMediaThumb(
                            key: ValueKey(
                              '${draft.eventId}|${draft.transactionId}|${draft.roomMsgKind}',
                            ),
                            wm: wm,
                            draft: draft,
                          ),
                        ],
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          _replyDraftTextPreview(draft),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput(BuildContext context, ConversationScreenWM wm) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          '> ',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        IconButton(
          icon: Icon(Icons.attach_file, color: theme.colorScheme.primary),
          onPressed: wm.showAttachMenu,
          tooltip: 'Attach',
        ),
        Expanded(
          child: TextField(
            controller: wm.messageController,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: wm.replyDraft.value != null
                  ? 'Write a reply…'
                  : 'Type your message...',
              hintStyle: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsetsDirectional.only(start: 8),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 0.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 1,
                ),
              ),
            ),
            onSubmitted: (_) => wm.sendMessage(),
            maxLines: null,
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: wm.composerHasText,
          builder: (context, hasText, _) {
            if (hasText) {
              return IconButton(
                icon: Icon(Icons.send, color: theme.colorScheme.primary),
                onPressed: wm.sendMessage,
                tooltip: 'Send message',
              );
            }
            return IconButton(
              icon: Icon(Icons.mic_rounded, color: theme.colorScheme.primary),
              onPressed: wm.showVoiceRecordSheet,
              tooltip: 'Record voice message',
            );
          },
        ),
      ],
    );
  }

  Widget _acceptInviteWidget(ConversationScreenWM wm) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                'You have been invited to this room',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TerminalButton(
                    text: 'ACCEPT',
                    onPressed: wm.acceptInvite,
                    icon: Icons.check,
                  ),
                  TerminalButton(
                    text: 'REJECT',
                    onPressed: wm.rejectInvite,
                    icon: Icons.close,
                    isPrimary: false,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void goBack(BuildContext context) {
    NavigatorService.pop(context);
  }

  @override
  void showRoomInfo(BuildContext context) {
    // Navigation is handled in [ConversationScreenWM.showRoomInfo].
  }
}

const double _kReplyDraftThumb = 52;

/// Thumbnail or kind placeholder for the reply banner (no filename).
class _ReplyDraftMediaThumb extends StatefulWidget {
  const _ReplyDraftMediaThumb({
    super.key,
    required this.wm,
    required this.draft,
  });

  final ConversationScreenWM wm;
  final Message draft;

  @override
  State<_ReplyDraftMediaThumb> createState() => _ReplyDraftMediaThumbState();
}

class _ReplyDraftMediaThumbState extends State<_ReplyDraftMediaThumb> {
  late final Future<Uint8List?> _thumbFuture;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    if (d.roomMsgKind == RoomMessageKind.audio) {
      _thumbFuture = Future<Uint8List?>.value(null);
    } else {
      final id = d.eventId.isNotEmpty ? d.eventId : d.transactionId;
      _thumbFuture = widget.wm.fetchRoomMessageMedia(id, thumbnail: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.draft;
    final border = theme.colorScheme.outlineVariant.withValues(alpha: 0.6);
    final bg = theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.45);

    Widget framed(Widget child) {
      return SizedBox(
        width: _kReplyDraftThumb,
        height: _kReplyDraftThumb,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border),
            color: bg,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: child,
          ),
        ),
      );
    }

    if (d.roomMsgKind == RoomMessageKind.audio) {
      return framed(
        Center(
          child: Icon(
            Icons.audiotrack,
            size: 26,
            color: theme.colorScheme.primary.withValues(alpha: 0.9),
          ),
        ),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _thumbFuture,
      builder: (context, snapshot) {
        final bh = d.mediaBlurhash.trim();
        final canBlur = bh.isNotEmpty &&
            (d.roomMsgKind == RoomMessageKind.image ||
                d.roomMsgKind == RoomMessageKind.video ||
                d.roomMsgKind == RoomMessageKind.file);
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (canBlur) {
            return framed(
              BlurHash(hash: bh, imageFit: BoxFit.cover),
            );
          }
          return framed(
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes != null &&
            bytes.isNotEmpty &&
            _replyThumbLooksLikeRaster(bytes)) {
          return framed(
            Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => canBlur
                  ? BlurHash(hash: bh, imageFit: BoxFit.cover)
                  : _replyDraftKindPlaceholder(d.roomMsgKind, theme),
            ),
          );
        }
        if (canBlur) {
          return framed(
            BlurHash(hash: bh, imageFit: BoxFit.cover),
          );
        }
        return framed(_replyDraftKindPlaceholder(d.roomMsgKind, theme));
      },
    );
  }
}

bool _replyThumbLooksLikeRaster(Uint8List data) {
  if (data.length < 12) return false;
  if (data.length >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) {
    return true;
  }
  if (data.length >= 8 &&
      data[0] == 0x89 &&
      data[1] == 0x50 &&
      data[2] == 0x4E &&
      data[3] == 0x47) {
    return true;
  }
  if (data.length >= 6 &&
      data[0] == 0x47 &&
      data[1] == 0x49 &&
      data[2] == 0x46) {
    final g = String.fromCharCodes(data.sublist(0, 6));
    return g == 'GIF87a' || g == 'GIF89a';
  }
  if (data.length >= 12 &&
      data[0] == 0x52 &&
      data[1] == 0x49 &&
      data[2] == 0x46 &&
      data[8] == 0x57 &&
      data[9] == 0x45 &&
      data[10] == 0x42 &&
      data[11] == 0x50) {
    return true;
  }
  return false;
}

Widget _replyDraftKindPlaceholder(RoomMessageKind kind, ThemeData theme) {
  final c = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85);
  final icon = switch (kind) {
    RoomMessageKind.image => Icons.image_outlined,
    RoomMessageKind.video => Icons.videocam_outlined,
    RoomMessageKind.file => Icons.insert_drive_file_outlined,
    RoomMessageKind.audio => Icons.audiotrack,
    _ => Icons.perm_media_outlined,
  };
  return Center(child: Icon(icon, size: 26, color: c));
}
