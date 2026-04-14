import 'dart:async';

import 'package:elementary/elementary.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/presentation/widgets/typing_dots_indicator.dart';
import 'package:matrix/src/core/timeline_raster_thumb.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
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
import 'package:matrix/src/theme/matrix_theme.dart';
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
    this.implyLeading = true,
  }) : super(conversationScreenWMFactory);

  final String roomId;
  final String roomName;
  final ChatRoomStatus status;

  /// When `false` (e.g. split-pane desktop), no back chevron on the app bar.
  final bool implyLeading;

  @override
  Widget build(ConversationScreenWM wm) {
    return ValueListenableBuilder<ConversationState>(
      valueListenable: wm.roomState,
      builder: (context, state, _) {
        final resolvedTitle = state.maybeWhen(
          loaded: (_, ri) {
            final n = ri.name.trim();
            return n.isNotEmpty ? n : roomName;
          },
          orElse: () => roomName,
        );
        final title = isDesktopTargetPlatform()
            ? resolvedTitle
            : resolvedTitle.toUpperCase();
        return TerminalScreen(
          title: title,
          automaticallyImplyLeading: implyLeading,
          actions: [
            if (status == ChatRoomStatus.joined)
              IconButton(
                icon: const Icon(Icons.call_outlined),
                tooltip: 'Call',
                onPressed: wm.showCallOptions,
              ),
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
            if (status == ChatRoomStatus.joined)
              ValueListenableBuilder<bool>(
                valueListenable: wm.timelineSearchOpen,
                builder: (context, open, _) {
                  return IconButton(
                    icon: Icon(open ? Icons.close : Icons.search),
                    tooltip: open ? 'Close search' : 'Search in conversation',
                    onPressed: wm.toggleTimelineSearch,
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
          ValueListenableBuilder<bool>(
            valueListenable: wm.timelineSearchOpen,
            builder: (context, open, _) {
              if (!open || status != ChatRoomStatus.joined) {
                return const SizedBox.shrink();
              }
              final scheme = Theme.of(context).colorScheme;
              final theme = Theme.of(context);
              final desktop = isDesktopTargetPlatform();
              return ListenableBuilder(
                listenable: Listenable.merge([
                  wm.timelineSearchController,
                  wm.timelineSearchUiRevision,
                ]),
                builder: (context, _) {
                  final n = wm.timelineSearchMatchCount;
                  final cur = wm.timelineSearchCurrentDisplayIndex;
                  final q = wm.timelineSearchController.text.trim();
                  final hasQuery = q.isNotEmpty;
                  final showNoMatch = hasQuery &&
                      (n == 0 || wm.timelineSearchHadJumpToHitFailure);
                  final canUp =
                      !showNoMatch && wm.timelineSearchCanGoTowardHistory;
                  final canDown =
                      !showNoMatch && wm.timelineSearchCanGoTowardLatest;
                  final radius = BorderRadius.circular(18);
                  final mono = theme.textTheme.labelMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  );
                  final fieldBorder = OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: desktop
                          ? scheme.outlineVariant.withValues(alpha: 0.65)
                          : MatrixTheme.matrixAccent.withValues(alpha: 0.35),
                    ),
                  );
                  final fieldFocused = OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: desktop
                          ? scheme.primary
                          : MatrixTheme.matrixAccent,
                      width: 1.5,
                    ),
                  );
                  final fieldFill = desktop
                      ? scheme.surface.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.04);
                  final hintColor = desktop
                      ? scheme.onSurfaceVariant.withValues(alpha: 0.75)
                      : MatrixTheme.matrixDarkGreen.withValues(alpha: 0.85);
                  final inputColor = desktop
                      ? scheme.onSurface
                      : MatrixTheme.matrixLightGreen;
                  final statusColor = showNoMatch
                      ? (desktop
                          ? scheme.error.withValues(alpha: 0.9)
                          : MatrixTheme.warningOrange.withValues(alpha: 0.95))
                      : (desktop
                          ? scheme.onSurfaceVariant
                          : MatrixTheme.matrixAccent.withValues(alpha: 0.88));
                  final statusText = !hasQuery
                      ? 'Live highlight'
                      : showNoMatch
                          ? 'No match found'
                          : 'Match $cur / $n';

                  return Padding(
                    padding: EdgeInsets.fromLTRB(desktop ? 10 : 12, 8, desktop ? 10 : 12, 6),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(
                          width: 1,
                          color: desktop
                              ? scheme.outlineVariant.withValues(alpha: 0.5)
                              : MatrixTheme.matrixAccent.withValues(alpha: 0.42),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (desktop ? scheme.primary : MatrixTheme.matrixAccent)
                                .withValues(alpha: desktop ? 0.07 : 0.14),
                            blurRadius: desktop ? 18 : 22,
                            spreadRadius: -2,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        gradient: desktop
                            ? null
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  MatrixTheme.terminalBlack.withValues(alpha: 0.78),
                                  MatrixTheme.terminalBackground.withValues(alpha: 0.9),
                                ],
                              ),
                        color: desktop
                            ? scheme.surfaceContainerLow.withValues(alpha: 0.94)
                            : null,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: wm.timelineSearchController,
                                    textInputAction: TextInputAction.search,
                                    cursorColor: desktop
                                        ? scheme.primary
                                        : MatrixTheme.matrixAccent,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: inputColor,
                                      height: 1.25,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Search conversation',
                                      hintStyle: theme.textTheme.bodyMedium
                                          ?.copyWith(color: hintColor),
                                      prefixIcon: Icon(
                                        Icons.search_rounded,
                                        size: 22,
                                        color: desktop
                                            ? scheme.primary
                                            : MatrixTheme.matrixAccent
                                                .withValues(alpha: 0.85),
                                      ),
                                      suffixIcon: hasQuery
                                          ? IconButton(
                                              tooltip: 'Clear',
                                              visualDensity:
                                                  VisualDensity.compact,
                                              icon: Icon(
                                                Icons.close_rounded,
                                                size: 20,
                                                color: hintColor,
                                              ),
                                              onPressed: () {
                                                wm.timelineSearchController
                                                    .clear();
                                              },
                                            )
                                          : null,
                                      filled: true,
                                      fillColor: fieldFill,
                                      isDense: true,
                                      border: fieldBorder,
                                      enabledBorder: fieldBorder,
                                      focusedBorder: fieldFocused,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 10,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Tooltip(
                                  message:
                                      'Jump to the first message on a chosen date',
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => unawaited(
                                        wm.openTimelineSearchDateJump(
                                          context,
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        width: 44,
                                        height: 44,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: desktop
                                                ? scheme.outlineVariant
                                                    .withValues(alpha: 0.7)
                                                : MatrixTheme.matrixAccent
                                                    .withValues(alpha: 0.4),
                                          ),
                                          color: desktop
                                              ? scheme.surfaceContainerHighest
                                                  .withValues(alpha: 0.5)
                                              : Colors.white
                                                  .withValues(alpha: 0.05),
                                        ),
                                        child: Icon(
                                          Icons.event_rounded,
                                          size: 22,
                                          color: desktop
                                              ? scheme.primary
                                              : MatrixTheme.matrixAccent,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.radar_rounded,
                                  size: 16,
                                  color: statusColor.withValues(alpha: 0.85),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    statusText,
                                    style: mono?.copyWith(
                                      color: statusColor,
                                      letterSpacing: 0.3,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: desktop
                                          ? scheme.outlineVariant
                                              .withValues(alpha: 0.55)
                                          : MatrixTheme.matrixAccent
                                              .withValues(alpha: 0.28),
                                    ),
                                    color: desktop
                                        ? scheme.surface.withValues(alpha: 0.65)
                                        : Colors.white.withValues(alpha: 0.04),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _searchNavIcon(
                                        tooltip:
                                            'Older match (earlier in history)',
                                        icon: Icons.keyboard_arrow_up_rounded,
                                        enabled: canUp,
                                        onPressed: wm.timelineSearchTowardHistory,
                                        scheme: scheme,
                                        desktop: desktop,
                                      ),
                                      Container(
                                        width: 1,
                                        height: 22,
                                        color: desktop
                                            ? scheme.outlineVariant
                                                .withValues(alpha: 0.45)
                                            : MatrixTheme.matrixAccent
                                                .withValues(alpha: 0.2),
                                      ),
                                      _searchNavIcon(
                                        tooltip: 'Newer match (toward latest)',
                                        icon:
                                            Icons.keyboard_arrow_down_rounded,
                                        enabled: canDown,
                                        onPressed: wm.timelineSearchTowardLatest,
                                        scheme: scheme,
                                        desktop: desktop,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          // Messages list
          Expanded(
            // Avatar MXC map updates per bubble only (see PaginatedMessageList), not here.
            child: ListenableBuilder(
              listenable: Listenable.merge([
                wm.roomState,
                TimelineLocalHiddenStore.revision,
                wm.timelineSearchOpen,
                wm.timelineSearchController,
                wm.timelineSearchUiRevision,
              ]),
              builder: (context, child) {
                final state = wm.roomState.value;
                final theme = Theme.of(context);
                final searchHighlight = wm.timelineSearchOpen.value
                    ? wm.timelineSearchController.text.trim()
                    : '';
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
                      key: ValueKey(roomId),
                      roomId: roomId,
                      senderAvatarMxcByUserId: wm.senderAvatarMxcByUserId,
                      loadMessageMedia: wm.fetchRoomMessageMedia,
                      loadSenderAvatar: wm.fetchUserAvatarThumbnail,
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
                      onBecameAtBottom: wm.onTimelineScrolledToBottom,
                      onLeftNewestEdge: wm.onTimelineLeftNewestEdge,
                      jumpToEventNotifier: wm.jumpToTimelineEventId,
                      scrollToLatestNotifier: wm.scrollTimelineToLatest,
                      isGroupRoom: !roomInfo.isDirect,
                      onToggleReaction: wm.toggleTimelineReaction,
                      onShowReactionReactors: wm.showReactionReactorsSheet,
                      onPollVote: wm.voteOnPoll,
                      onShowMessageActions: (ctx, m, o) =>
                          wm.showMessageActionsMenu(ctx, m, o),
                      onSenderAvatarTap: wm.onSenderAvatarTap,
                      timelineSearchHighlightQuery:
                          searchHighlight.isEmpty ? null : searchHighlight,
                      onProgrammaticJumpFailure:
                          wm.handleProgrammaticJumpFailureForTimelineSearch,
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
                            ValueListenableBuilder<List<String>>(
                              valueListenable: wm.roomTypingUserIds,
                              builder: (context, typingIds, _) {
                                if (typingIds.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                final theme = Theme.of(context);
                                final accent = theme.colorScheme.primary
                                    .withValues(alpha: 0.92);
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    12,
                                    6,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      TypingDotsIndicator(
                                        color: accent,
                                        dotSize: 5,
                                        spacing: 4,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          wm.typingIndicatorLabel(typingIds),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: accent,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
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
      },
    );
  }

  Widget _pendingOutgoingInviteBanner(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.55)),
          color: scheme.primary.withValues(alpha: 0.1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.hourglass_top_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'INVITATION PENDING',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Waiting for them to accept. Hides when they join.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.88),
                        fontSize: 12,
                        height: 1.3,
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
              Text(bytesLabel, style: theme.textTheme.bodySmall),
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
      RoomMessageKind.call => false,
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
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.55,
          ),
          border: Border(left: BorderSide(color: accent, width: 3)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '> REPLY TO ${draft.displayName}',
                      textAlign: TextAlign.start,
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
                          _ReplyDraftMediaThumb(
                            key: ValueKey(
                              '${draft.eventId}|${draft.transactionId}|${draft.roomMsgKind}',
                            ),
                            wm: wm,
                            draft: draft,
                          ),
                          const SizedBox(width: 10),
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
                                  textAlign: TextAlign.start,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.72),
                                  ),
                                );
                              },
                            ),
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
                          textAlign: TextAlign.start,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.8,
                            ),
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
    final desktop = isDesktopTargetPlatform();
    final fieldPadding = EdgeInsets.symmetric(
      horizontal: desktop ? 14 : 10,
      vertical: desktop ? 12 : 8,
    );
    // Sharp corners on mobile: rounded outline reads like extra IME chrome above the keyboard.
    final fieldBorderRadius =
        desktop ? BorderRadius.circular(8) : BorderRadius.zero;
    // [TextFieldTapRegion] + same [groupId] as [TextField] so taps on send/attach are not
    // "outside" the field — [onTapOutside] would otherwise dismiss the keyboard.
    return TextFieldTapRegion(
      groupId: EditableText,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          desktop ? 12 : 8,
          8,
          desktop ? 12 : 8,
          desktop ? 14 : 10,
        ),
        child: Row(
          children: [
          Text(
            '> ',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            child: IconButton(
              icon: Icon(Icons.attach_file, color: theme.colorScheme.primary),
              onPressed: wm.showAttachMenu,
              tooltip: 'Attach',
            ),
          ),
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) {
                  return KeyEventResult.ignored;
                }
                if (event.logicalKey != LogicalKeyboardKey.enter &&
                    event.logicalKey != LogicalKeyboardKey.numpadEnter) {
                  return KeyEventResult.ignored;
                }
                if (HardwareKeyboard.instance.isShiftPressed) {
                  return KeyEventResult.ignored;
                }
                wm.sendMessage();
                return KeyEventResult.handled;
              },
              child: TextField(
                controller: wm.messageController,
                focusNode: wm.composerFocusNode,
                groupId: EditableText,
                autocorrect: !desktop,
                enableSuggestions: !desktop,
                keyboardAppearance: theme.brightness,
                onChanged: wm.onComposerTextChanged,
                onTapOutside: (_) {
                  FocusManager.instance.primaryFocus?.unfocus();
                },
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: wm.replyDraft.value != null
                      ? 'Write a reply…'
                      : 'Type your message...',
                  hintStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  contentPadding: fieldPadding,
                  isDense: !desktop,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: fieldBorderRadius,
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 0.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: fieldBorderRadius,
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 1,
                    ),
                  ),
                ),
                onSubmitted: (_) => wm.sendMessage(),
                maxLines: null,
                textInputAction: TextInputAction.newline,
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: wm.composerHasText,
            builder: (context, hasText, _) {
              // Single non-focusable control so swapping send/mic does not steal TextField focus
              // (avoids keyboard dismiss + reopen when sending).
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  canRequestFocus: false,
                  onTap: hasText ? wm.sendMessage : wm.showVoiceRecordSheet,
                  borderRadius: BorderRadius.circular(22),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      hasText ? Icons.send : Icons.mic_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
        ),
      ),
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

  Future<Uint8List?> _loadReplyDraftThumb(Message d) async {
    final id = d.eventId.isNotEmpty ? d.eventId : d.transactionId;
    final raw = await widget.wm.fetchRoomMessageMedia(id, thumbnail: true);
    if (raw == null || raw.isEmpty) return null;
    if (!_replyThumbLooksLikeRaster(raw)) return null;
    final e = timelineThumbDecodeExtentPx(_kReplyDraftThumb);
    final small = await encodeRasterPngFitBox(
      raw,
      targetWidthPx: e,
      targetHeightPx: e,
    );
    return small ?? raw;
  }

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    if (d.roomMsgKind == RoomMessageKind.audio) {
      _thumbFuture = Future<Uint8List?>.value(null);
    } else {
      _thumbFuture = _loadReplyDraftThumb(d);
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
        final canBlur =
            bh.isNotEmpty &&
            (d.roomMsgKind == RoomMessageKind.image ||
                d.roomMsgKind == RoomMessageKind.video ||
                d.roomMsgKind == RoomMessageKind.file);
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (canBlur) {
            return framed(BlurHash(hash: bh, imageFit: BoxFit.cover));
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
          final thumbDecode = timelineThumbImageDecodeCacheParams(
            logicalWidth: _kReplyDraftThumb,
            logicalHeight: _kReplyDraftThumb,
            context: context,
          );
          return framed(
            Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: thumbDecode.cacheWidth,
              cacheHeight: thumbDecode.cacheHeight,
              errorBuilder: (_, __, ___) => canBlur
                  ? BlurHash(hash: bh, imageFit: BoxFit.cover)
                  : _replyDraftKindPlaceholder(d.roomMsgKind, theme),
            ),
          );
        }
        if (canBlur) {
          return framed(BlurHash(hash: bh, imageFit: BoxFit.cover));
        }
        return framed(_replyDraftKindPlaceholder(d.roomMsgKind, theme));
      },
    );
  }
}

bool _replyThumbLooksLikeRaster(Uint8List data) {
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

Widget _searchNavIcon({
  required String tooltip,
  required IconData icon,
  required bool enabled,
  required VoidCallback onPressed,
  required ColorScheme scheme,
  required bool desktop,
}) {
  final color = enabled
      ? (desktop ? scheme.primary : MatrixTheme.matrixAccent)
      : (desktop
          ? scheme.onSurfaceVariant.withValues(alpha: 0.32)
          : MatrixTheme.matrixDarkGreen.withValues(alpha: 0.42));
  return IconButton(
    tooltip: tooltip,
    onPressed: enabled ? onPressed : null,
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    style: IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: Icon(icon, size: 22, color: color),
  );
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
