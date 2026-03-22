import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:path/path.dart' as p;
import 'package:matrix/src/core/open_in_app_url.dart';
import 'package:matrix/src/core/timeline_local_hidden_store.dart';
import 'package:matrix/src/features/conversation/domain/models/conversation_state.dart'
    hide MessageType;
import 'package:matrix/src/features/conversation/presentation/widgets/link_preview_cards.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix_sdk/matrix_sdk.dart'
    show
        EventSendStateKind,
        Message,
        MessageReactionEntry,
        MessageType,
        RoomMessageKind;

/// Preset keys for [m.reaction](https://spec.matrix.org/latest/client-server-api/#mreaction) quick picker.
const List<String> kTimelineQuickReactions = [
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '🎉',
];

/// Additional presets for the scrollable grid (no overlap with [kTimelineQuickReactions]).
const String _kTimelineDeletedBubbleSubtitle =
    'This message is no longer visible.';

/// Local “delete for me” — message still exists for others; hidden on this device only.
Widget _timelineRemovedOnDeviceBubbleBody(
  BuildContext context,
  Color accentColor,
) {
  final theme = Theme.of(context);
  final muted = theme.colorScheme.onSurfaceVariant;
  const titleSize = 12.5;
  const subSize = 11.5;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        Icons.visibility_off_outlined,
        size: 18,
        color: accentColor.withValues(alpha: 0.92),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Message removed',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                fontSize: titleSize,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'You hid this message on this device.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                fontStyle: FontStyle.italic,
                height: 1.3,
                fontSize: subSize,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Full-width deleted state inside a message bubble (redacted event).
Widget _timelineDeletedBubbleBody(BuildContext context, Color accentColor) {
  final theme = Theme.of(context);
  final muted = theme.colorScheme.onSurfaceVariant;
  const titleSize = 12.5;
  const subSize = 11.5;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        Icons.chat_bubble_outline,
        size: 18,
        color: accentColor.withValues(alpha: 0.92),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deleted message',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                fontSize: titleSize,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _kTimelineDeletedBubbleSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                fontStyle: FontStyle.italic,
                height: 1.3,
                fontSize: subSize,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Inline reply target was redacted — tap still jumps to that timeline row.
Widget _timelineDeletedReplyTargetRow(BuildContext context) {
  final theme = Theme.of(context);
  final muted = theme.colorScheme.onSurfaceVariant;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Icon(Icons.link_off_rounded, size: 17, color: muted),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Original message was deleted',
          style: theme.textTheme.bodySmall?.copyWith(
            color: muted,
            fontStyle: FontStyle.italic,
            height: 1.25,
          ),
        ),
      ),
    ],
  );
}

/// Same reaction grid as long-press on a bubble; used from the message ⋮ menu.
Future<void> openTimelineQuickReactionPicker(
  BuildContext context, {
  required Future<void> Function(String reactionKey) onToggle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: MatrixTheme.terminalBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      side: BorderSide(color: MatrixTheme.terminalBorder),
    ),
    builder: (ctx) => _QuickReactionBottomSheet(
      onPick: (key) => onToggle(key),
    ),
  );
}

const List<String> kTimelinePresetReactionsMore = [
  '🔥',
  '🎉',
  '😊',
  '😁',
  '👏',
  '💯',
  '✨',
  '🤔',
  '😭',
  '😡',
  '🤝',
  '💪',
  '🙏',
  '😍',
  '🤣',
  '😅',
  '😎',
  '🥳',
  '👀',
  '💔',
  '🤷',
  '‼️',
  '❓',
  '✅',
  '⚠️',
  '🚀',
  '⭐',
  '💡',
  '🔔',
  '📌',
  '🏆',
  '🎯',
  '💀',
  '👌',
  '🤩',
  '🥰',
  '😴',
  '🤨',
  '🙌',
  '💜',
  '💙',
  '💚',
  '💛',
  '🧡',
  '🤍',
  '🖤',
  '👋',
  '✌️',
  '🤞',
  '🫶',
  '😘',
  '🤗',
  '😇',
  '💘',
  '🫡',
  '🥹',
  '👆',
  '👇',
  '☀️',
  '🌙',
  '☕',
  '🍕',
  '🎂',
  '🎮',
  '🐱',
  '🐶',
];

/// Result of loading older messages: [older] is the newly loaded chunk (or empty
/// when the parent updated state with full list); [hasMore] indicates if more
/// can be loaded.
typedef LoadOlderResult = (List<Message> older, bool hasMore);

class PaginatedMessageList extends StatefulWidget {
  const PaginatedMessageList({
    super.key,
    required this.roomId,
    required this.loadMessageMedia,
    required this.initialMessages, // List<Message> ordered oldest → newest
    required this.loadOlder, // Future<LoadOlderResult> Function(Message oldest)
    this.onRetryFailedSend,
    required this.onVisibleRange, // Optional: for read receipts
    this.onOpenAttachment,
    this.jumpToEventNotifier,
    this.onStartReply,
    this.isGroupRoom = false,
    required this.onToggleReaction,
    required this.onShowReactionReactors,
    this.onPollVote,
    this.onShowMessageActions,
  });

  final String roomId;
  final Future<Uint8List?> Function(String eventId, {bool thumbnail})
  loadMessageMedia;

  /// Opens full attachment in the in-app viewer (or external app for office files).
  final Future<void> Function(Message message)? onOpenAttachment;
  final List<Message> initialMessages;
  final Future<LoadOlderResult> Function(Message oldest) loadOlder;
  final Future<void> Function(String transactionId)? onRetryFailedSend;
  final void Function(Message firstVisible, Message lastVisible)?
  onVisibleRange;

  /// When set to a non-empty event id (e.g. from room info), scrolls that bubble into view.
  final ValueNotifier<String?>? jumpToEventNotifier;

  /// Swipe horizontally on a message row to start inline reply (requires [Message.eventId]).
  final void Function(Message message)? onStartReply;

  /// When true, long-pressing a reaction chip opens [onShowReactionReactors]; tap still toggles.
  final bool isGroupRoom;

  /// Toggle add/remove reaction (`m.reaction`); chip tap, quick picker, and sheet remove action.
  final Future<void> Function(Message message, String reactionKey)
  onToggleReaction;

  /// Group rooms: long-press reaction chip → who reacted (bottom sheet).
  final void Function(
    BuildContext context,
    Message message,
    MessageReactionEntry entry,
  )
  onShowReactionReactors;

  /// MSC3381 poll vote; [pollEventId] is the poll start [Message.eventId].
  final Future<void> Function(String pollEventId, List<String> answerIds)?
  onPollVote;

  /// ⋮ menu: reply, react, delete, …
  final void Function(BuildContext context, Message message)?
  onShowMessageActions;

  @override
  State<PaginatedMessageList> createState() => PaginatedMessageListState();
}

class PaginatedMessageListState extends State<PaginatedMessageList> {
  final _controller = ScrollController();
  bool _scrollListenerAttached = false;
  bool _isLoadingOlder = false;
  bool _hasMore = true;
  int _unseenNewCount = 0;
  String _lastTailKey = '';
  String? _pendingJumpEventId;
  GlobalKey? _jumpKey;
  int _jumpRetryFrames = 0;
  int _jumpResolveGeneration = 0;

  /// Event / transaction id to frame after a successful jump-to-message.
  String? _jumpHighlightId;
  Timer? _jumpHighlightTimer;

  static const Duration _jumpHighlightDuration = Duration(seconds: 3);

  /// Scrolls to and briefly highlights [eventId], reusing the same path as
  /// [jumpToEventNotifier]. Clears then re-assigns the notifier so repeated
  /// jumps to the same id still notify listeners.
  ///
  /// Notifies [jumpToEventNotifier]. For a repeat jump to the same id, clears
  /// then sets on the next microtask so [ValueNotifier] listeners run twice.
  static void requestScrollToEvent(
    ValueNotifier<String?>? notifier,
    String eventId,
  ) {
    if (notifier == null || eventId.isEmpty) return;
    if (notifier.value == eventId) {
      notifier.value = null;
      scheduleMicrotask(() {
        notifier.value = eventId;
      });
    } else {
      notifier.value = eventId;
    }
  }

  bool get _isAtBottom {
    // With reverse:true, bottom == pixels <= 20
    return !_controller.hasClients || _controller.position.pixels <= 20;
  }

  @override
  void initState() {
    super.initState();
    _lastTailKey = _computeTailKey();
    widget.jumpToEventNotifier?.addListener(_onJumpNotifier);
    if (widget.initialMessages.isNotEmpty) {
      _hasMore =
          widget.initialMessages.first.messageType != MessageType.timelineStart;
      _controller.addListener(_onScroll);
      _scrollListenerAttached = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.initialMessages.length < 5 && _hasMore) {
          _maybeLoadOlder();
        }
      });
    }
  }

  @override
  void dispose() {
    _jumpHighlightTimer?.cancel();
    widget.jumpToEventNotifier?.removeListener(_onJumpNotifier);
    if (_scrollListenerAttached) {
      _controller.removeListener(_onScroll);
    }
    _controller.dispose();
    super.dispose();
  }

  String _stableMessageKey(Message m) {
    if (m.eventId.isNotEmpty) return 'e:${m.eventId}';
    if (m.transactionId.isNotEmpty) return 't:${m.transactionId}';
    return 'x:${m.timestamp}:${m.content.hashCode}';
  }

  String _computeTailKey() {
    final m = widget.initialMessages;
    if (m.isEmpty) return '';
    return _stableMessageKey(m.last);
  }

  void _onJumpNotifier() {
    final id = widget.jumpToEventNotifier?.value;
    if (id == null || id.isEmpty) return;
    _jumpResolveGeneration++;
    final gen = _jumpResolveGeneration;
    unawaited(_resolveJumpToEvent(id, gen));
  }

  Future<void> _nextFrame() {
    final c = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  /// Loads older pages until [eventId] is in [initialMessages] or history ends.
  static const int _maxJumpPaginationPages = 200;

  bool _messageMatchesJumpTarget(Message m, String id) {
    if (id.isEmpty) return false;
    return (m.eventId.isNotEmpty && m.eventId == id) ||
        (m.transactionId.isNotEmpty && m.transactionId == id);
  }

  Future<void> _resolveJumpToEvent(String eventId, int gen) async {
    var pagesLoaded = 0;
    while (mounted && gen == _jumpResolveGeneration) {
      if (widget.initialMessages.any(
        (m) => _messageMatchesJumpTarget(m, eventId),
      )) {
        _startJumpScrollToEvent(eventId);
        return;
      }

      if (widget.initialMessages.isEmpty) {
        _abortJumpToEvent(gen, 'No messages in this room yet.');
        return;
      }

      final first = widget.initialMessages.first;
      if (first.messageType == MessageType.timelineStart || !_hasMore) {
        _abortJumpToEvent(
          gen,
          'That message is not in the history available on this device.',
        );
        return;
      }

      if (pagesLoaded >= _maxJumpPaginationPages) {
        _abortJumpToEvent(
          gen,
          'Stopped searching after loading many pages. Try again closer in time.',
        );
        return;
      }

      while (mounted && gen == _jumpResolveGeneration && _isLoadingOlder) {
        await Future<void>.delayed(const Duration(milliseconds: 24));
      }
      if (!mounted || gen != _jumpResolveGeneration) return;

      pagesLoaded++;
      await _performLoadOlderPage();
      if (!mounted || gen != _jumpResolveGeneration) return;

      await _nextFrame();
    }
  }

  void _abortJumpToEvent(int gen, String message) {
    if (gen != _jumpResolveGeneration) return;
    widget.jumpToEventNotifier?.value = null;
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Index in [display] (newest → oldest) of the list row that builds a bubble
  /// for this jump target, or `null` if every matching row is filtered out.
  int? _jumpTargetDisplayIndex(String id, List<Message> display) {
    for (var i = 0; i < display.length; i++) {
      final message = display[i];
      if ([
        MessageType.dateDivider,
        MessageType.readMarker,
        MessageType.timelineStart,
      ].contains(message.messageType)) {
        continue;
      }
      if (message.messageType == MessageType.message &&
          message.content.isEmpty &&
          !_wantsMediaPreview(message)) {
        continue;
      }
      if (_messageMatchesJumpTarget(message, id)) {
        return i;
      }
    }
    return null;
  }

  /// [SliverList.builder] only lays out items near the viewport. Nudge scroll
  /// offset so the target row is built and [GlobalKey.currentContext] exists.
  ///
  /// With [reverse: true], newer messages use lower scroll offsets; older use
  /// higher offsets toward [ScrollPosition.maxScrollExtent].
  void _applyJumpScrollNudge(List<Message> display, int idx, int attempt) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final max = pos.maxScrollExtent;
    if (max <= 0) return;
    final denom = display.length <= 1 ? 1 : (display.length - 1);
    final t = idx / denom;
    var goal = max * t;
    if (attempt > 0 && attempt <= 28) {
      goal += (attempt % 9 - 4) * pos.viewportDimension * 0.2;
    } else if (attempt > 28) {
      const segments = 18;
      final seg = (attempt - 29) % segments;
      goal = max * seg / (segments - 1);
    }
    pos.jumpTo(goal.clamp(0.0, max));
  }

  static const int _maxJumpScrollAttempts = 80;

  void _startJumpScrollToEvent(String id) {
    _jumpHighlightTimer?.cancel();
    _jumpHighlightTimer = null;
    setState(() {
      _jumpHighlightId = null;
      _pendingJumpEventId = id;
      _jumpKey = GlobalKey();
    });
    _jumpRetryFrames = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _completeJumpScroll();
    });
  }

  void _completeJumpScroll() {
    final id = _pendingJumpEventId;
    final key = _jumpKey;
    if (!mounted || id == null || key == null) {
      return;
    }

    final ctx = key.currentContext;
    if (ctx != null) {
      // Clear jump keys only after ensureVisible finishes; otherwise the subtree
      // remounts (GlobalKey → ValueKey) and the scroll animation is lost.
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ).then((_) {
        if (!mounted) return;
        final highlightId = id;
        _jumpRetryFrames = 0;
        _jumpHighlightTimer?.cancel();
        _jumpHighlightTimer = Timer(_jumpHighlightDuration, () {
          if (!mounted) return;
          setState(() => _jumpHighlightId = null);
        });
        setState(() {
          _pendingJumpEventId = null;
          _jumpKey = null;
          _jumpHighlightId = highlightId;
        });
        widget.jumpToEventNotifier?.value = null;
      });
      return;
    }

    final display = widget.initialMessages.reversed.toList(growable: false);
    final idx = _jumpTargetDisplayIndex(id, display);
    if (idx == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That message is not shown as a row in this timeline.',
            ),
          ),
        );
      }
      _jumpRetryFrames = 0;
      setState(() {
        _pendingJumpEventId = null;
        _jumpKey = null;
      });
      widget.jumpToEventNotifier?.value = null;
      return;
    }

    if (_jumpRetryFrames < _maxJumpScrollAttempts) {
      if (_controller.hasClients) {
        _applyJumpScrollNudge(display, idx, _jumpRetryFrames);
      }
      _jumpRetryFrames++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _completeJumpScroll();
      });
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not scroll to that message.')),
      );
    }
    _jumpRetryFrames = 0;
    setState(() {
      _pendingJumpEventId = null;
      _jumpKey = null;
    });
    widget.jumpToEventNotifier?.value = null;
  }

  static const double _loadOlderThresholdPx = 80;

  void _onScroll() {
    if (!_controller.hasClients) return;
    // Load older when scrolled near top (reverse:true so top = maxScrollExtent)
    final pos = _controller.position;
    if (pos.pixels >= pos.maxScrollExtent - _loadOlderThresholdPx) {
      _maybeLoadOlder();
    }

    widget.onVisibleRange?.call(_firstVisible(), _lastVisible());
  }

  @override
  void didUpdateWidget(PaginatedMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jumpToEventNotifier != widget.jumpToEventNotifier) {
      oldWidget.jumpToEventNotifier?.removeListener(_onJumpNotifier);
      widget.jumpToEventNotifier?.addListener(_onJumpNotifier);
    }
    if (widget.initialMessages.isNotEmpty && !_scrollListenerAttached) {
      _scrollListenerAttached = true;
      _hasMore =
          widget.initialMessages.first.messageType != MessageType.timelineStart;
      _controller.addListener(_onScroll);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.initialMessages.length < 5 && _hasMore) {
          _maybeLoadOlder();
        }
      });
    }
    // Parent replaces the list from the Rust stream; end of backlog is a virtual row.
    if (widget.initialMessages.isNotEmpty &&
        widget.initialMessages.first.messageType == MessageType.timelineStart &&
        _hasMore) {
      setState(() => _hasMore = false);
    }

    final newTail = _computeTailKey();
    if (newTail.isNotEmpty && newTail != _lastTailKey && _isAtBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom();
      });
    }
    _lastTailKey = newTail;
  }

  Future<void> _maybeLoadOlder() async {
    if (_isLoadingOlder || !_hasMore || widget.initialMessages.isEmpty) return;
    if (widget.initialMessages.first.messageType == MessageType.timelineStart) {
      return;
    }
    await _performLoadOlderPage();
  }

  /// Shared pagination step for scroll-to-load and jump-to-event resolution.
  Future<void> _performLoadOlderPage() async {
    if (!_hasMore || widget.initialMessages.isEmpty) return;
    final oldest = widget.initialMessages.first;
    if (oldest.messageType == MessageType.timelineStart) return;

    setState(() => _isLoadingOlder = true);

    final beforeMax = _controller.hasClients
        ? _controller.position.maxScrollExtent
        : 0.0;

    final (older, hasMore) = await widget.loadOlder(oldest);

    if (!mounted) return;

    if (older.isNotEmpty) {
      setState(() {
        widget.initialMessages.insertAll(0, older);
        _isLoadingOlder = false;
        _hasMore =
            hasMore &&
            widget.initialMessages.first.messageType !=
                MessageType.timelineStart;
      });
    } else {
      setState(() {
        _isLoadingOlder = false;
        _hasMore = hasMore;
      });
    }

    // Adjust scroll so content doesn't jump (works for both insert and state-replace).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final afterMax = _controller.position.maxScrollExtent;
      final delta = afterMax - beforeMax;
      _controller.jumpTo(_controller.position.pixels + delta);
    });
  }

  // Call this when a brand-new message arrives (push from server)
  void addIncoming(Message m) {
    final shouldAutoscroll = _isAtBottom;
    setState(() => widget.initialMessages.add(m));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (shouldAutoscroll) {
        _scrollToBottom();
      } else {
        setState(() => _unseenNewCount += 1);
      }
    });
  }

  void _scrollToBottom() {
    if (!_controller.hasClients) return;
    _controller.animateTo(
      0, // because reverse:true
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    setState(() => _unseenNewCount = 0);
  }

  Message _firstVisible() {
    // Approx via pixels/estimatedExtent, or keep an ItemPositionsListener (see note below)
    return widget.initialMessages.first;
  }

  Message _lastVisible() {
    return widget.initialMessages.last;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.initialMessages.isEmpty) {
      return Center(
        child: Text(
          'NO MESSAGES YET\nSTART THE CONVERSATION',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      );
    }

    final display = widget.initialMessages.reversed.toList(
      growable: false,
    ); // newest → oldest for UI

    return Stack(
      children: [
        NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            if (_isAtBottom && _unseenNewCount != 0) {
              setState(() => _unseenNewCount = 0);
            }
            return false;
          },
          child: CustomScrollView(
            controller: _controller,
            reverse: true,
            slivers: [
              SliverList.builder(
                itemCount: display.length,
                itemBuilder: (context, index) {
                  final message = display[index];

                  // Virtual rows — no bubble. Real [MessageType.message] can have
                  // empty [content] (e.g. image/file with no caption); those must
                  // still build so jump-to-event GlobalKeys attach.
                  // Redacted events also have empty body — must build so the deleted placeholder shows.
                  if ([
                    MessageType.dateDivider,
                    MessageType.readMarker,
                    MessageType.timelineStart,
                  ].contains(message.messageType)) {
                    return const SizedBox.shrink();
                  }
                  if (message.messageType == MessageType.message &&
                      message.content.isEmpty &&
                      !_wantsMediaPreview(message) &&
                      !message.isRedacted &&
                      !TimelineLocalHiddenStore.isHidden(message)) {
                    return const SizedBox.shrink();
                  }

                  final jumpKey = _jumpKey;
                  final pendingId = _pendingJumpEventId;
                  final useJumpKey =
                      jumpKey != null &&
                      pendingId != null &&
                      pendingId.isNotEmpty &&
                      _messageMatchesJumpTarget(message, pendingId);
                  return KeyedSubtree(
                    key: useJumpKey
                        ? jumpKey
                        : ValueKey(
                            message.eventId.isNotEmpty
                                ? message.eventId
                                : (message.transactionId.isNotEmpty
                                      ? message.transactionId
                                      : 'm-${message.timestamp}-${message.content.hashCode}'),
                          ),
                    child: _buildMessageBubble(
                      message,
                      index: index,
                      prev: index + 1 < display.length
                          ? display[index + 1]
                          : null,
                      roomId: widget.roomId,
                      loadMessageMedia: widget.loadMessageMedia,
                      onOpenAttachment: widget.onOpenAttachment,
                      jumpToEventNotifier: widget.jumpToEventNotifier,
                      onStartReply: widget.onStartReply,
                      isGroupRoom: widget.isGroupRoom,
                      onToggleReaction: widget.onToggleReaction,
                      onShowReactionReactors: widget.onShowReactionReactors,
                      onPollVote: widget.onPollVote,
                      jumpHighlighted:
                          _jumpHighlightId != null &&
                          _messageMatchesJumpTarget(message, _jumpHighlightId!),
                    ),
                  );
                },
              ),
              if (_hasMore && !_isLoadingOlder)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: TextButton.icon(
                        onPressed: _maybeLoadOlder,
                        icon: const Icon(Icons.arrow_upward, size: 20),
                        label: const Text('Load older messages'),
                      ),
                    ),
                  ),
                ),
              if (_isLoadingOlder)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
          ),
        ),

        // New messages pill
        if (_unseenNewCount > 0 && !_isAtBottom)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _scrollToBottom,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      '$_unseenNewCount new ${_unseenNewCount == 1 ? "message" : "messages"}',
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageBubble(
    Message m, {
    int? index,
    Message? prev,
    required String roomId,
    required Future<Uint8List?> Function(String eventId, {bool thumbnail})
    loadMessageMedia,
    Future<void> Function(Message message)? onOpenAttachment,
    ValueNotifier<String?>? jumpToEventNotifier,
    void Function(Message message)? onStartReply,
    required bool isGroupRoom,
    required Future<void> Function(Message message, String reactionKey)
    onToggleReaction,
    required void Function(
      BuildContext context,
      Message message,
      MessageReactionEntry entry,
    )
    onShowReactionReactors,
    Future<void> Function(String pollEventId, List<String> answerIds)?
    onPollVote,
    bool jumpHighlighted = false,
  }) {
    final bubble = MessageBubble(
      message: m,
      roomId: roomId,
      isOutgoing: m.isOwn,
      loadMessageMedia: loadMessageMedia,
      onRetryFailedSend: widget.onRetryFailedSend,
      onOpenAttachment: onOpenAttachment,
      jumpToEventNotifier: jumpToEventNotifier,
      onStartReply: onStartReply,
      isGroupRoom: isGroupRoom,
      onToggleReaction: onToggleReaction,
      onShowReactionReactors: onShowReactionReactors,
      onPollVote: onPollVote,
      onOpenMessageActions: widget.onShowMessageActions != null
          ? (ctx) => widget.onShowMessageActions!(ctx, m)
          : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (jumpHighlighted)
          Builder(
            builder: (context) {
              final scheme = Theme.of(context).colorScheme;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.tertiary, width: 2.5),
                  color: scheme.tertiary.withValues(alpha: 0.12),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.tertiary.withValues(alpha: 0.35),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: bubble,
              );
            },
          )
        else
          bubble,
      ],
    );
  }
}

bool _shouldShowInlineReplyMediaThumb(Message message) {
  if (message.inReplyToEventId.isEmpty) return false;
  if (message.inReplyToParentRedacted) return false;
  return switch (message.inReplyToRoomMsgKind) {
    RoomMessageKind.image => true,
    RoomMessageKind.video => true,
    RoomMessageKind.audio => true,
    RoomMessageKind.file => true,
    RoomMessageKind.text => false,
    RoomMessageKind.poll => false,
    RoomMessageKind.other => false,
  };
}

String? _inlineReplyFormatBytes(BigInt bytes) {
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

String? _inlineReplyTargetMetaLine(Message m) {
  final parts = <String>[];
  final mime = m.inReplyToMediaMimetype.trim();
  if (mime.isNotEmpty) parts.add(mime);
  final sz = _inlineReplyFormatBytes(m.inReplyToMediaSizeBytes);
  if (sz != null) parts.add(sz);
  if (m.inReplyToMediaPreviewWidth > 0 && m.inReplyToMediaPreviewHeight > 0) {
    parts.add(
      '${m.inReplyToMediaPreviewWidth}×${m.inReplyToMediaPreviewHeight}',
    );
  }
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

class _InlineReplyQuote extends StatelessWidget {
  const _InlineReplyQuote({
    required this.message,
    required this.headerColor,
    required this.borderColor,
    required this.loadMessageMedia,
    this.jumpToEventNotifier,
  });

  final Message message;
  final Color headerColor;
  final Color borderColor;
  final Future<Uint8List?> Function(String eventId, {bool thumbnail})
  loadMessageMedia;
  final ValueNotifier<String?>? jumpToEventNotifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final senderLabel = message.replyToSenderDisplay.isEmpty
        ? 'UNKNOWN'
        : message.replyToSenderDisplay;

    final showMedia = _shouldShowInlineReplyMediaThumb(message);
    final meta = _inlineReplyTargetMetaLine(message);
    final parentDeleted = message.inReplyToParentRedacted;

    final inner = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: borderColor, width: 3)),
        color: theme.colorScheme.surface.withValues(alpha: 0.22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '> RE: $senderLabel',
            style: theme.textTheme.labelMedium?.copyWith(
              color: headerColor,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          if (parentDeleted) ...[
            const SizedBox(height: 6),
            _timelineDeletedReplyTargetRow(context),
          ],
          if (!parentDeleted && !showMedia && message.inReplyToPreview.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              message.inReplyToPreview,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                height: 1.3,
              ),
            ),
          ],
          if (!parentDeleted && showMedia) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InlineReplyTargetThumb(
                  key: ValueKey('ir-${message.inReplyToEventId}'),
                  eventId: message.inReplyToEventId,
                  kind: message.inReplyToRoomMsgKind,
                  blurhash: message.inReplyToMediaBlurhash,
                  loadMessageMedia: loadMessageMedia,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _timelineMediaKindTag(message.inReplyToRoomMsgKind),
                        style: _timelineMono(
                          theme,
                          size: 11,
                          weight: FontWeight.bold,
                          color: headerColor.withValues(alpha: 0.88),
                        ),
                      ),
                      if (meta != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          meta,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.72,
                            ),
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (jumpToEventNotifier == null) {
      return inner;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => PaginatedMessageListState.requestScrollToEvent(
        jumpToEventNotifier,
        message.inReplyToEventId,
      ),
      child: inner,
    );
  }
}

const double _kInlineReplyThumb = 52;

class _InlineReplyTargetThumb extends StatefulWidget {
  const _InlineReplyTargetThumb({
    super.key,
    required this.eventId,
    required this.kind,
    required this.blurhash,
    required this.loadMessageMedia,
  });

  final String eventId;
  final RoomMessageKind kind;
  final String blurhash;
  final Future<Uint8List?> Function(String eventId, {bool thumbnail})
  loadMessageMedia;

  @override
  State<_InlineReplyTargetThumb> createState() =>
      _InlineReplyTargetThumbState();
}

class _InlineReplyTargetThumbState extends State<_InlineReplyTargetThumb> {
  late final Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    if (widget.kind == RoomMessageKind.audio) {
      _future = Future<Uint8List?>.value(null);
    } else {
      _future = widget.loadMessageMedia(widget.eventId, thumbnail: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = theme.colorScheme.outlineVariant.withValues(alpha: 0.55);
    final bg = theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.4);

    Widget framed(Widget child) {
      return SizedBox(
        width: _kInlineReplyThumb,
        height: _kInlineReplyThumb,
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

    if (widget.kind == RoomMessageKind.audio) {
      return framed(
        Center(
          child: Icon(
            Icons.audiotrack,
            size: 24,
            color: theme.colorScheme.primary.withValues(alpha: 0.85),
          ),
        ),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          final bh = widget.blurhash.trim();
          if (bh.isNotEmpty &&
              (widget.kind == RoomMessageKind.image ||
                  widget.kind == RoomMessageKind.video)) {
            return framed(BlurHash(hash: bh, imageFit: BoxFit.cover));
          }
          return framed(
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes != null &&
            bytes.isNotEmpty &&
            _isTimelineRasterBytes(bytes)) {
          return framed(
            Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) =>
                  _inlineReplyKindPlaceholder(widget.kind, theme),
            ),
          );
        }
        return framed(_inlineReplyKindPlaceholder(widget.kind, theme));
      },
    );
  }
}

Widget _inlineReplyKindPlaceholder(RoomMessageKind kind, ThemeData theme) {
  final c = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.82);
  final icon = switch (kind) {
    RoomMessageKind.image => Icons.image_outlined,
    RoomMessageKind.video => Icons.videocam_outlined,
    RoomMessageKind.file => Icons.insert_drive_file_outlined,
    RoomMessageKind.audio => Icons.audiotrack,
    RoomMessageKind.poll => Icons.poll_outlined,
    RoomMessageKind.text => Icons.chat_bubble_outline,
    RoomMessageKind.other => Icons.perm_media_outlined,
  };
  return Center(child: Icon(icon, size: 24, color: c));
}

class _PollTallyRow {
  const _PollTallyRow({
    required this.id,
    required this.text,
    required this.count,
    required this.voters,
  });

  final String id;
  final String text;
  final int count;
  final List<String> voters;
}

/// Parsed MSC3381 poll state from [Message.pollStateJson] (fallback: options only).
class _ParsedPollState {
  const _ParsedPollState({
    required this.kind,
    required this.maxSelections,
    required this.ended,
    required this.edited,
    required this.rows,
    required this.totalSelections,
  });

  final String kind;
  final int maxSelections;
  final bool ended;
  final bool edited;
  final List<_PollTallyRow> rows;
  final int totalSelections;
}

_ParsedPollState? _parsePollState(Message message) {
  final stateRaw = message.pollStateJson.trim();
  if (stateRaw.isNotEmpty) {
    try {
      final decoded = jsonDecode(stateRaw);
      if (decoded is Map<String, dynamic>) {
        final kind = decoded['kind']?.toString() ?? 'undisclosed';
        final maxSel = switch (decoded['maxSelections']) {
          final int x => x,
          final num x => x.toInt(),
          _ => 1,
        };
        final ended = decoded['ended'] == true;
        final edited = decoded['edited'] == true;
        final total = switch (decoded['totalSelections']) {
          final int x => x,
          final num x => x.toInt(),
          _ => 0,
        };
        final tallies = decoded['tallies'];
        final rows = <_PollTallyRow>[];
        if (tallies is List) {
          for (final e in tallies) {
            if (e is! Map) continue;
            final id = e['id']?.toString() ?? '';
            final text = e['text']?.toString() ?? '';
            if (id.isEmpty) continue;
            final c = switch (e['count']) {
              final int x => x,
              final num x => x.toInt(),
              _ => 0,
            };
            final voters = <String>[];
            final vv = e['voters'];
            if (vv is List) {
              for (final v in vv) {
                final s = v?.toString() ?? '';
                if (s.isNotEmpty) voters.add(s);
              }
            }
            rows.add(
              _PollTallyRow(
                id: id,
                text: text.isEmpty ? id : text,
                count: c,
                voters: voters,
              ),
            );
          }
        }
        if (rows.isNotEmpty) {
          return _ParsedPollState(
            kind: kind,
            maxSelections: maxSel.clamp(1, 99),
            ended: ended,
            edited: edited,
            rows: rows,
            totalSelections: total,
          );
        }
      }
    } catch (_) {}
  }
  final optRaw = message.pollOptionsJson.trim();
  if (optRaw.isEmpty) return null;
  try {
    final decoded = jsonDecode(optRaw);
    if (decoded is! Map || decoded['answers'] is! List) return null;
    final rows = <_PollTallyRow>[];
    for (final e in decoded['answers'] as List) {
      if (e is! Map) continue;
      final id = e['id']?.toString() ?? '';
      final text = e['text']?.toString() ?? '';
      if (id.isEmpty || text.isEmpty) continue;
      rows.add(_PollTallyRow(id: id, text: text, count: 0, voters: const []));
    }
    if (rows.isEmpty) return null;
    return _ParsedPollState(
      kind: 'undisclosed',
      maxSelections: 1,
      ended: false,
      edited: false,
      rows: rows,
      totalSelections: 0,
    );
  } catch (_) {
    return null;
  }
}

/// MSC3381 poll: kind badges, results, voting (single- or multi-select).
class _PollMessageBody extends StatefulWidget {
  const _PollMessageBody({
    super.key,
    required this.message,
    required this.accent,
    required this.isOutgoing,
    this.onVote,
  });

  static const Color _incomingPollText = Color(0xFF58A6FF);

  final Message message;
  final Color accent;
  final bool isOutgoing;
  final Future<void> Function(List<String> answerIds)? onVote;

  @override
  State<_PollMessageBody> createState() => _PollMessageBodyState();
}

class _PollMessageBodyState extends State<_PollMessageBody> {
  final Set<String> _selected = {};

  @override
  void didUpdateWidget(covariant _PollMessageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.pollStateJson != widget.message.pollStateJson ||
        oldWidget.message.eventId != widget.message.eventId) {
      _selected.clear();
    }
  }

  Widget _chip(String label, {bool emphasize = false}) {
    final c = emphasize ? widget.accent : widget.accent.withValues(alpha: 0.88);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: c.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(3),
        color: c.withValues(alpha: emphasize ? 0.16 : 0.08),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          fontSize: 9,
          fontFamily: MatrixTheme.fontFamily,
          height: 1,
        ),
      ),
    );
  }

  String _kindLabel(String kind) {
    return switch (kind) {
      'disclosed' => 'LIVE RESULTS',
      'undisclosed' => 'SECRET',
      _ => 'POLL',
    };
  }

  String _kindSubtitle(String kind) {
    return switch (kind) {
      'disclosed' => 'Vote counts and voters are visible.',
      'undisclosed' => 'Vote details stay hidden until the poll ends.',
      _ => 'MSC3381 poll',
    };
  }

  Future<void> _submitVotes(List<String> ids) async {
    final cb = widget.onVote;
    if (cb == null || ids.isEmpty) return;
    await cb(ids);
    if (mounted) setState(() => _selected.clear());
  }

  void _toggleSelect(String id, int maxSel) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        if (_selected.length >= maxSel) {
          if (maxSel <= 1) {
            _selected
              ..clear()
              ..add(id);
          } else {
            return;
          }
        } else {
          _selected.add(id);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final parsed = _parsePollState(widget.message);
    final rows = parsed?.rows ?? <_PollTallyRow>[];
    final kind = parsed?.kind ?? 'undisclosed';
    final maxSel = parsed?.maxSelections ?? 1;
    final ended = parsed?.ended ?? false;
    final edited = parsed?.edited ?? false;
    final totalSel = parsed?.totalSelections ?? 0;
    final denom = totalSel > 0 ? totalSel : 1;
    final canVote =
        widget.onVote != null && widget.message.eventId.isNotEmpty && !ended;

    final qColor = widget.isOutgoing
        ? (theme.textTheme.bodyMedium?.color ?? scheme.onSurface)
        : _PollMessageBody._incomingPollText;

    final panelBorder = widget.accent.withValues(alpha: 0.38);
    final panelBg = scheme.surfaceContainerLowest.withValues(alpha: 0.55);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: panelBorder),
        color: panelBg,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.how_to_vote_outlined,
                  size: 18,
                  color: widget.accent.withValues(alpha: 0.95),
                ),
                const SizedBox(width: 8),
                Text(
                  'POLL',
                  style: TextStyle(
                    color: widget.accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    fontSize: 11,
                    fontFamily: MatrixTheme.fontFamily,
                  ),
                ),
                const Spacer(),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  children: [
                    _chip(_kindLabel(kind)),
                    if (ended) _chip('CLOSED'),
                    if (edited) _chip('EDITED'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _kindSubtitle(kind),
              style: TextStyle(
                color: MatrixTheme.matrixDarkGreen.withValues(alpha: 0.92),
                height: 1.35,
                fontSize: 11,
                fontFamily: MatrixTheme.fontFamily,
              ),
            ),
            const SizedBox(height: 10),
            Divider(
              height: 1,
              thickness: 1,
              color: panelBorder.withValues(alpha: 0.65),
            ),
            const SizedBox(height: 10),
            Text(
              widget.message.content,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: qColor,
                fontWeight: FontWeight.w700,
                height: 1.35,
                fontFamily: MatrixTheme.fontFamily,
              ),
            ),
            if (parsed != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.tune,
                    size: 14,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Up to $maxSel choice${maxSel == 1 ? '' : 's'} · '
                      '$totalSel response${totalSel == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                        fontFamily: MatrixTheme.fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (widget.message.eventId.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: widget.accent.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sending poll…',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        fontFamily: MatrixTheme.fontFamily,
                      ),
                    ),
                  ],
                ),
              )
            else if (rows.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: 1,
                color: panelBorder.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 10),
              if (canVote && maxSel <= 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 15,
                        color: widget.accent.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Tap an option to vote',
                          style: TextStyle(
                            color: widget.accent.withValues(alpha: 0.88),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: MatrixTheme.fontFamily,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ...rows.map((row) {
                final frac = (row.count / denom).clamp(0.0, 1.0);
                final showVoters = kind == 'disclosed' && row.voters.isNotEmpty;
                final voterPreview = row.voters.length > 3
                    ? '${row.voters.take(3).join(', ')} · +${row.voters.length - 3}'
                    : row.voters.join(', ');
                final pctText = totalSel > 0
                    ? '${((row.count * 100) / totalSel).round()}%'
                    : '—';
                final singleTapVote = canVote && maxSel <= 1;

                Widget optionBody = Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (canVote && maxSel > 1) ...[
                            Padding(
                              padding: const EdgeInsets.only(right: 8, top: 1),
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: Checkbox(
                                  value: _selected.contains(row.id),
                                  onChanged: (_) =>
                                      _toggleSelect(row.id, maxSel),
                                  fillColor: WidgetStateProperty.resolveWith((
                                    states,
                                  ) {
                                    if (states.contains(WidgetState.selected)) {
                                      return widget.accent;
                                    }
                                    return null;
                                  }),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          ],
                          Expanded(
                            child: Text(
                              row.text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                                fontFamily: MatrixTheme.fontFamily,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${row.count}',
                                style: TextStyle(
                                  color: widget.accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  fontFamily: MatrixTheme.fontFamily,
                                ),
                              ),
                              Text(
                                pctText,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 10,
                                  fontFamily: MatrixTheme.fontFamily,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: frac,
                          minHeight: 6,
                          backgroundColor: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.45),
                          color: widget.accent.withValues(alpha: 0.72),
                        ),
                      ),
                      if (showVoters)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Voters: $voterPreview',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.95,
                              ),
                              fontSize: 10,
                              height: 1.25,
                              fontFamily: MatrixTheme.fontFamily,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                );

                if (singleTapVote) {
                  optionBody = Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _submitVotes([row.id]),
                      borderRadius: BorderRadius.circular(8),
                      splashColor: widget.accent.withValues(alpha: 0.12),
                      highlightColor: widget.accent.withValues(alpha: 0.06),
                      child: optionBody,
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: widget.accent.withValues(alpha: 0.22),
                      ),
                      color: scheme.surface.withValues(alpha: 0.35),
                    ),
                    child: optionBody,
                  ),
                );
              }),
              if (canVote && maxSel > 1) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => _submitVotes(_selected.toList()),
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.accent,
                      foregroundColor: scheme.surface,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      'Submit votes (${_selected.length}/$maxSel)',
                      style: TextStyle(
                        fontFamily: MatrixTheme.fontFamily,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.roomId,
    required this.isOutgoing,
    required this.loadMessageMedia,
    this.onRetryFailedSend,
    this.onOpenAttachment,
    this.jumpToEventNotifier,
    this.onStartReply,
    required this.isGroupRoom,
    required this.onToggleReaction,
    required this.onShowReactionReactors,
    this.onPollVote,
    this.onOpenMessageActions,
  });

  /// Incoming bubbles: blue accent so they read clearly against terminal-green “sent” styling.
  static const Color _receivedAccent = Color(0xFF58A6FF);

  final Message message;
  final String roomId;
  final bool isOutgoing;
  final Future<Uint8List?> Function(String eventId, {bool thumbnail})
  loadMessageMedia;
  final Future<void> Function(String transactionId)? onRetryFailedSend;
  final Future<void> Function(Message message)? onOpenAttachment;
  final ValueNotifier<String?>? jumpToEventNotifier;
  final void Function(Message message)? onStartReply;
  final bool isGroupRoom;
  final Future<void> Function(Message message, String reactionKey)
  onToggleReaction;
  final void Function(
    BuildContext context,
    Message message,
    MessageReactionEntry entry,
  )
  onShowReactionReactors;

  final Future<void> Function(String pollEventId, List<String> answerIds)?
  onPollVote;

  /// ⋮ opens a sheet with reply / react / delete (parent supplies room actions).
  final void Function(BuildContext context)? onOpenMessageActions;

  bool get _canReactToMessage =>
      message.messageType == MessageType.message &&
      !message.isRedacted &&
      !TimelineLocalHiddenStore.isHidden(message) &&
      (message.eventId.isNotEmpty || message.transactionId.isNotEmpty);

  void _openQuickReactionPicker(BuildContext context) {
    openTimelineQuickReactionPicker(
      context,
      onToggle: (key) => onToggleReaction(message, key),
    );
  }

  void _onReactionChipTap(MessageReactionEntry e) {
    onToggleReaction(message, e.key);
  }

  /// Group rooms: long-press opens who-reacted sheet; tap toggles like DMs.
  void _onReactionChipLongPress(BuildContext context, MessageReactionEntry e) {
    if (!isGroupRoom) return;
    HapticFeedback.lightImpact();
    onShowReactionReactors(context, message, e);
  }

  /// Compact terminal-style reaction line (matches Matrix monospace / HUD cues).
  Widget _reactionsStrip(BuildContext context, Color accentColor) {
    if (!_canReactToMessage || message.reactions.isEmpty) {
      return const SizedBox.shrink();
    }
    final tagColor = accentColor.withValues(alpha: 0.5);
    final countStyle = MatrixTheme.messageTimeStyle.copyWith(
      fontSize: 9,
      height: 1,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '// RX',
              style: MatrixTheme.labelStyle.copyWith(
                fontSize: 9,
                letterSpacing: 2,
                color: tagColor,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: message.reactions.map((e) {
                final own = e.containsOwn;
                return InkWell(
                  onTap: () => _onReactionChipTap(e),
                  onLongPress: isGroupRoom
                      ? () => _onReactionChipLongPress(context, e)
                      : null,
                  borderRadius: BorderRadius.circular(3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: MatrixTheme.terminalDarkGreen.withValues(
                        alpha: 0.55,
                      ),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: own
                            ? MatrixTheme.matrixGreen.withValues(alpha: 0.5)
                            : MatrixTheme.terminalBorder,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          e.key,
                          textHeightBehavior: const TextHeightBehavior(
                            applyHeightToFirstAscent: false,
                            applyHeightToLastDescent: false,
                          ),
                          style: const TextStyle(fontSize: 12, height: 1.05),
                        ),
                        if (e.count > 1) ...[
                          const SizedBox(width: 3),
                          Text(
                            '×${e.count}',
                            style: countStyle.copyWith(
                              color: own
                                  ? MatrixTheme.matrixLightGreen.withValues(
                                      alpha: 0.85,
                                    )
                                  : MatrixTheme.matrixDarkGreen,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sendAccentColor = switch (message.sendState) {
      EventSendStateKind.failed => theme.colorScheme.error,
      EventSendStateKind.pending => theme.colorScheme.tertiary,
      EventSendStateKind.delivered => theme.colorScheme.primary,
    };
    final barColor = isOutgoing ? sendAccentColor : _receivedAccent;
    final pending = message.sendState == EventSendStateKind.pending;
    final hiddenLocal = TimelineLocalHiddenStore.isHidden(message);
    final canReply =
        onStartReply != null &&
        message.messageType == MessageType.message &&
        !message.isRedacted &&
        !hiddenLocal &&
        message.eventId.isNotEmpty;
    final showMenu =
        onOpenMessageActions != null &&
        message.messageType == MessageType.message &&
        !message.isRedacted &&
        !hiddenLocal;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,

            /// Swipe horizontally (toward thread start) to start inline reply.
            onHorizontalDragEnd: (details) {
              if (!canReply) return;
              final vx = details.velocity.pixelsPerSecond.dx;
              const threshold = 280.0;
              final rtl = Directionality.of(context) == TextDirection.rtl;
              // Swipe “outward” to reply: right in LTR, left in RTL (same as many chat apps).
              final swipeToReply = rtl ? vx < -threshold : vx > threshold;
              if (swipeToReply) {
                HapticFeedback.lightImpact();
                onStartReply!(message);
              }
            },

            /// Long-press opens the quick reaction picker (reply is swipe).
            onLongPress: _canReactToMessage
                ? () {
                    HapticFeedback.lightImpact();
                    _openQuickReactionPicker(context);
                  }
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '> ${message.displayName}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isOutgoing
                            ? theme.colorScheme.primary
                            : _receivedAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (pending) ...[
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (showMenu)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        iconSize: 20,
                        tooltip: 'Message actions',
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          onOpenMessageActions!(context);
                        },
                        icon: Icon(
                          Icons.more_horiz,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      message.formattedDate,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(color: barColor, width: 3),
                    ),
                    color: isOutgoing
                        ? theme.colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.5,
                          )
                        : theme.colorScheme.surfaceContainerLow.withValues(
                            alpha: 0.75,
                          ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.isRedacted)
                        _timelineDeletedBubbleBody(context, barColor)
                      else if (hiddenLocal)
                        _timelineRemovedOnDeviceBubbleBody(context, barColor)
                      else ...[
                      if (message.inReplyToEventId.isNotEmpty)
                        _InlineReplyQuote(
                          message: message,
                          headerColor: barColor,
                          borderColor: barColor.withValues(alpha: 0.75),
                          loadMessageMedia: loadMessageMedia,
                          jumpToEventNotifier: jumpToEventNotifier,
                        ),
                      if (message.roomMsgKind == RoomMessageKind.poll)
                        _PollMessageBody(
                          key: ValueKey(
                            '${message.eventId}_${message.pollStateJson.hashCode}',
                          ),
                          message: message,
                          accent: barColor,
                          isOutgoing: isOutgoing,
                          onVote:
                              onPollVote != null && message.eventId.isNotEmpty
                              ? (ids) => onPollVote!(message.eventId, ids)
                              : null,
                        )
                      else if (_wantsMediaPreview(message))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _MessageMediaPreview(
                            timelineMediaKey: message.eventId.isNotEmpty
                                ? message.eventId
                                : message.transactionId,
                            kind: message.roomMsgKind,
                            fileLabel: message.content,
                            caption: message.content,
                            mediaMimetype: message.mediaMimetype,
                            mediaSizeBytes: message.mediaSizeBytes,
                            mediaBlurhash: message.mediaBlurhash,
                            mediaPreviewWidth: message.mediaPreviewWidth,
                            mediaPreviewHeight: message.mediaPreviewHeight,
                            loadMessageMedia: loadMessageMedia,
                            onOpen:
                                onOpenAttachment != null &&
                                    (message.eventId.isNotEmpty ||
                                        message.transactionId.isNotEmpty)
                                ? () => onOpenAttachment!(message)
                                : null,
                          ),
                        )
                      else ...[
                        SelectableLinkify(
                          text: message.content,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isOutgoing ? null : _receivedAccent,
                          ),
                          linkStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: isOutgoing
                                ? theme.colorScheme.primary
                                : _receivedAccent,
                            decoration: TextDecoration.underline,
                            decorationColor: isOutgoing
                                ? theme.colorScheme.primary
                                : _receivedAccent,
                          ),
                          onOpen: (link) => openMatrixUrl(context, link.url),
                        ),
                        if (matrixLinkPreviewsJsonHasData(
                          message.linkPreviewsJson,
                        ))
                          MatrixLinkPreviewCards(
                            linkPreviewsJson: message.linkPreviewsJson,
                            accentColor: barColor,
                            compact: true,
                            onOpenUrl: (u) => openMatrixUrl(context, u),
                          ),
                      ],
                      ],
                      if (!message.isRedacted && !hiddenLocal)
                        _reactionsStrip(context, barColor),
                      if (message.sendState == EventSendStateKind.failed &&
                          message.sendError.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          message.sendError,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      if (message.sendState == EventSendStateKind.failed &&
                          message.sendRecoverable &&
                          message.transactionId.isNotEmpty &&
                          onRetryFailedSend != null) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () =>
                              onRetryFailedSend!(message.transactionId),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Retry send'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickReactionBottomSheet extends StatefulWidget {
  const _QuickReactionBottomSheet({required this.onPick});

  final void Function(String key) onPick;

  @override
  State<_QuickReactionBottomSheet> createState() =>
      _QuickReactionBottomSheetState();
}

class _QuickReactionBottomSheetState extends State<_QuickReactionBottomSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  static const int _maxKeyLen = 128;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _pick(String key) {
    if (key.isEmpty) return;
    Navigator.of(context).pop();
    widget.onPick(key);
  }

  void _submitCustom() {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    if (t.length > _maxKeyLen) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reaction key too long ($_maxKeyLen characters max)',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
      return;
    }
    _pick(t);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final h = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: SizedBox(
          height: (h * 0.52).clamp(320.0, h * 0.85),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    Text(
                      '// REACT',
                      style: MatrixTheme.labelStyle.copyWith(
                        letterSpacing: 3,
                        color: MatrixTheme.matrixDarkGreen,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: MatrixTheme.matrixGreen.withValues(alpha: 0.85),
                        size: 22,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    '> QUICK',
                    style: MatrixTheme.captionStyle.copyWith(fontSize: 10),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: kTimelineQuickReactions.map((emoji) {
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _pick(emoji),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: MatrixTheme.terminalBorder,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            color: MatrixTheme.terminalDarkGreen.withValues(
                              alpha: 0.45,
                            ),
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    '> PRESETS',
                    style: MatrixTheme.captionStyle.copyWith(fontSize: 10),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 1,
                  ),
                  itemCount: kTimelinePresetReactionsMore.length,
                  itemBuilder: (context, i) {
                    final emoji = kTimelinePresetReactionsMore[i];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _pick(emoji),
                        borderRadius: BorderRadius.circular(8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: MatrixTheme.terminalBorder.withValues(
                                alpha: 0.7,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        style: const TextStyle(fontSize: 22, height: 1.2),
                        decoration: InputDecoration(
                          hintText: 'Other — type or paste emoji',
                          hintStyle: MatrixTheme.hintStyle.copyWith(
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: MatrixTheme.terminalBlack,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: MatrixTheme.terminalBorder,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: MatrixTheme.terminalBorder,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: MatrixTheme.matrixGreen,
                              width: 1.5,
                            ),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submitCustom(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _submitCustom,
                      style: FilledButton.styleFrom(
                        backgroundColor: MatrixTheme.matrixDarkGreen,
                        foregroundColor: MatrixTheme.matrixLightGreen,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                      child: Text(
                        'SEND',
                        style: MatrixTheme.labelStyle.copyWith(fontSize: 11),
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
}

/// JPEG / PNG / GIF / WebP / BMP magic — matches Rust timeline thumbnail validation.
bool _isTimelineRasterBytes(Uint8List data) {
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

bool _isJpegTimelineBytes(Uint8List data) =>
    data.length >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF;

int _readUint16LeBe(Uint8List b, int offset, bool littleEndian) {
  final a = b[offset];
  final c = b[offset + 1];
  return littleEndian ? (a | (c << 8)) : ((a << 8) | c);
}

int _readUint32LeBe(Uint8List b, int offset, bool littleEndian) {
  if (littleEndian) {
    return b[offset] |
        (b[offset + 1] << 8) |
        (b[offset + 2] << 16) |
        (b[offset + 3] << 24);
  }
  return (b[offset] << 24) |
      (b[offset + 1] << 16) |
      (b[offset + 2] << 8) |
      b[offset + 3];
}

/// Reads TIFF IFD0 orientation tag (0x0112), 1–8 per JEITA EXIF spec.
int? _readTiffOrientationIfd0(Uint8List b, int tiffStart, int tiffEnd) {
  if (tiffStart + 8 > tiffEnd) return null;
  final le = b[tiffStart] == 0x49 && b[tiffStart + 1] == 0x49;
  final be = b[tiffStart] == 0x4D && b[tiffStart + 1] == 0x4D;
  if (!le && !be) return null;
  final ifd0Off = _readUint32LeBe(b, tiffStart + 4, le);
  var ifd = tiffStart + ifd0Off;
  if (ifd < tiffStart || ifd + 2 > tiffEnd) return null;
  final n = _readUint16LeBe(b, ifd, le);
  var p = ifd + 2;
  for (var i = 0; i < n && p + 12 <= tiffEnd; i++) {
    final tag = _readUint16LeBe(b, p, le);
    final type = _readUint16LeBe(b, p + 2, le);
    final count = _readUint32LeBe(b, p + 4, le);
    if (tag == 0x0112 && type == 3) {
      if (count == 1) {
        return _readUint16LeBe(b, p + 8, le);
      }
      final vo = _readUint32LeBe(b, p + 8, le);
      final vp = tiffStart + vo;
      if (vp + 2 <= tiffEnd) {
        return _readUint16LeBe(b, vp, le);
      }
      return null;
    }
    p += 12;
  }
  return null;
}

int? _tryExifOrientationFromApp1(
  Uint8List b,
  int payloadStart,
  int payloadEnd,
) {
  if (payloadEnd - payloadStart < 6) return null;
  if (b[payloadStart] != 0x45 ||
      b[payloadStart + 1] != 0x78 ||
      b[payloadStart + 2] != 0x69 ||
      b[payloadStart + 3] != 0x66 ||
      b[payloadStart + 4] != 0 ||
      b[payloadStart + 5] != 0) {
    return null;
  }
  final tiffStart = payloadStart + 6;
  final o = _readTiffOrientationIfd0(b, tiffStart, payloadEnd);
  if (o == null || o < 1 || o > 8) return null;
  return o;
}

/// EXIF orientation 1–8 for JPEG; 1 if absent or not JPEG.
int _jpegExifOrientation(Uint8List b) {
  if (!_isJpegTimelineBytes(b)) return 1;
  var i = 2;
  while (i + 3 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    if (marker == 0xD9) break;
    if (marker == 0xD8 || marker == 0x01) {
      i += 2;
      continue;
    }
    if (i + 4 > b.length) break;
    final segLen = _readUint16LeBe(b, i + 2, false);
    if (segLen < 2 || i + 2 + segLen > b.length) break;
    if (marker == 0xE1) {
      final payStart = i + 4;
      final payEnd = i + 2 + segLen;
      final o = _tryExifOrientationFromApp1(b, payStart, payEnd);
      if (o != null) return o;
    }
    i += 2 + segLen;
  }
  return 1;
}

/// Decoder pixel size → logical size for layout (swap when EXIF implies 90° steps).
Size _orientedIntrinsicForLayout(Size raw, int exifOrientation) {
  switch (exifOrientation) {
    case 5:
    case 6:
    case 7:
    case 8:
      return Size(raw.height, raw.width);
    default:
      return raw;
  }
}

/// [RotatedBox] quarter-turns (clockwise) to correct common EXIF orientations.
int _exifQuarterTurns(int exifOrientation) {
  switch (exifOrientation) {
    case 3:
      return 2;
    case 6:
      return 1;
    case 8:
      return 3;
    default:
      return 0;
  }
}

class _TimelinePreviewMeta {
  const _TimelinePreviewMeta(this.rawSize, this.exifOrientation);

  final Size rawSize;
  final int exifOrientation;
}

/// Tiny images (e.g. 1×1 MXC placeholders) pass [_isTimelineRasterBytes] but
/// would paint as a flat slab if stretched. Returns null for those; otherwise
/// raw decoder size + JPEG EXIF orientation for layout and rotation.
Future<_TimelinePreviewMeta?> _timelineImagePreviewMeta(Uint8List data) async {
  if (data.isEmpty) return null;
  final exif = _jpegExifOrientation(data);
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    final w = frame.image.width;
    final h = frame.image.height;
    frame.image.dispose();
    if (w < 1 || h < 1) return null;
    final longest = w > h ? w : h;
    if (longest < 64) return null;
    return _TimelinePreviewMeta(Size(w.toDouble(), h.toDouble()), exif);
  } catch (_) {
    return null;
  } finally {
    codec?.dispose();
  }
}

/// Fixed thumbnail frame when an event thumbnail is shown (remaining width → metadata).
const double _kTimelineThumbPortraitW = 45;
const double _kTimelineThumbPortraitH = 60;
const double _kTimelineThumbLandscapeW = 80;
const double _kTimelineThumbLandscapeH = 45;

/// Fixed timeline thumb frame (portrait vs landscape) from known pixel size; EXIF not applied.
Size _timelineLoadingThumbFrameSize(int w, int h) {
  if (w > 0 && h > 0) {
    final oriented = _orientedIntrinsicForLayout(
      Size(w.toDouble(), h.toDouble()),
      1,
    );
    final portrait = oriented.height > oriented.width;
    return Size(
      portrait ? _kTimelineThumbPortraitW : _kTimelineThumbLandscapeW,
      portrait ? _kTimelineThumbPortraitH : _kTimelineThumbLandscapeH,
    );
  }
  return const Size(_kTimelineThumbPortraitW, _kTimelineThumbPortraitH);
}

bool _wantsMediaPreview(Message m) {
  final lookup = m.eventId.isNotEmpty ? m.eventId : m.transactionId;
  if (lookup.isEmpty) return false;
  switch (m.roomMsgKind) {
    case RoomMessageKind.image:
    case RoomMessageKind.file:
    case RoomMessageKind.video:
    case RoomMessageKind.audio:
      return true;
    case RoomMessageKind.text:
    case RoomMessageKind.poll:
    case RoomMessageKind.other:
      return false;
  }
}

String _timelineExtLower(String label) {
  final base = p.basename(label.trim());
  final dot = base.lastIndexOf('.');
  if (dot < 0 || dot >= base.length - 1) return '';
  return base.substring(dot + 1).toLowerCase();
}

IconData _timelineFileIcon(String ext) {
  switch (ext) {
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'doc':
    case 'docx':
    case 'odt':
    case 'rtf':
      return Icons.description_outlined;
    case 'xls':
    case 'xlsx':
    case 'xlsm':
    case 'xlsb':
    case 'csv':
    case 'ods':
      return Icons.table_chart_outlined;
    case 'ppt':
    case 'pptx':
    case 'odp':
      return Icons.slideshow_outlined;
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
      return Icons.folder_zip_outlined;
    case 'txt':
    case 'md':
    case 'log':
      return Icons.article_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

/// Human-readable size from Matrix `info.size` when present.
String? _formatTimelineMediaSize(BigInt bytes) {
  if (bytes <= BigInt.zero) return null;
  double v;
  try {
    v = bytes.toDouble();
  } catch (_) {
    return '${bytes.toString()} B';
  }
  if (!v.isFinite || v <= 0) {
    return '${bytes.toString()} B';
  }
  const units = ['B', 'KB', 'MB', 'GB'];
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
    if (!v.isFinite) return '${bytes.toString()} B';
  }
  if (u == 0) return '${bytes.toString()} B';
  final decimals = v >= 100 || (v - v.round()).abs() < 1e-6 ? 0 : 1;
  return '${v.toStringAsFixed(decimals)} ${units[u]}';
}

String _timelineAttachmentMimeLabel(
  String mediaMimetype,
  RoomMessageKind kind,
  String extLower,
) {
  final m = mediaMimetype.trim();
  if (m.isNotEmpty) return m;
  return switch (kind) {
    RoomMessageKind.image => 'image',
    RoomMessageKind.video => 'video',
    RoomMessageKind.audio => 'audio',
    RoomMessageKind.file =>
      extLower.isNotEmpty ? extLower.toUpperCase() : 'file',
    RoomMessageKind.poll => 'poll',
    RoomMessageKind.text => 'text',
    RoomMessageKind.other => 'attachment',
  };
}

String _timelineMediaKindTag(RoomMessageKind kind) => switch (kind) {
  RoomMessageKind.image => 'IMG',
  RoomMessageKind.video => 'VID',
  RoomMessageKind.audio => 'AUD',
  RoomMessageKind.file => 'FILE',
  RoomMessageKind.poll => 'POLL',
  _ => 'MEDIA',
};

TextStyle _timelineMono(
  ThemeData theme, {
  required double size,
  FontWeight? weight,
  Color? color,
  double height = 1.25,
}) => TextStyle(
  fontFamily: MatrixTheme.fontFamily,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
);

/// Dotted horizontal rule that does **not** use [LayoutBuilder], so it is safe
/// under [IntrinsicHeight] (e.g. [_mediaTerminalPanel] in a [SliverList] row).
Widget _terminalDottedRule(ThemeData theme) {
  return SizedBox(
    height: 11,
    width: double.infinity,
    child: CustomPaint(
      painter: _TerminalDottedRulePainter(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
      ),
    ),
  );
}

class _TerminalDottedRulePainter extends CustomPainter {
  _TerminalDottedRulePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final paint = Paint()..color = color;
    final y = size.height / 2;
    const step = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: 1.6, height: 1.6),
          const Radius.circular(0.6),
        ),
        paint,
      );
      x += step;
    }
  }

  @override
  bool shouldRepaint(covariant _TerminalDottedRulePainter oldDelegate) =>
      oldDelegate.color != color;
}

Widget _mediaTerminalDetailsColumn({
  required ThemeData theme,
  required RoomMessageKind kind,
  required String fileLabel,
  required String mediaMimetype,
  required BigInt mediaSizeBytes,
  required int mediaPreviewWidth,
  required int mediaPreviewHeight,
  required bool showTapHint,
}) {
  final ext = _timelineExtLower(fileLabel);
  final mime = _timelineAttachmentMimeLabel(mediaMimetype, kind, ext);
  final sizeStr = _formatTimelineMediaSize(mediaSizeBytes);
  final metaBits = <String>[mime];
  if (sizeStr != null) metaBits.add(sizeStr);
  final metaLine = metaBits.join(' · ');
  final tag = _timelineMediaKindTag(kind);
  final accent = theme.colorScheme.primary;
  final showImageVideoResolution =
      (kind == RoomMessageKind.image || kind == RoomMessageKind.video) &&
      mediaPreviewWidth > 0 &&
      mediaPreviewHeight > 0;
  final dimLabel = showImageVideoResolution
      ? '$mediaPreviewWidth×$mediaPreviewHeight'
      : '';

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: accent.withValues(alpha: 0.14),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                tag,
                style: _timelineMono(
                  theme,
                  size: 9,
                  weight: FontWeight.w700,
                  color: accent.withValues(alpha: 0.92),
                  height: 1.1,
                ),
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
      const SizedBox(height: 6),
      _terminalDottedRule(theme),
      if (metaLine.isNotEmpty) ...[
        const SizedBox(height: 5),
        Text(
          metaLine,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: _timelineMono(
            theme,
            size: 11.5,
            weight: FontWeight.w500,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.95),
          ),
        ),
      ],
      if (dimLabel.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          'res · $dimLabel',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _timelineMono(
            theme,
            size: 10,
            weight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
          ),
        ),
      ],
      if (ext.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          'fmt · ${ext.toUpperCase()}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _timelineMono(
            theme,
            size: 10,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.82),
          ),
        ),
      ],
      if (showTapHint) ...[
        const Spacer(),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '// open',
            style: _timelineMono(
              theme,
              size: 9.5,
              color: accent.withValues(alpha: 0.55),
              height: 1.1,
            ),
          ),
        ),
      ],
    ],
  );
}

/// Thumb + metadata row for media bubbles (no outer border; matches plain bubble chrome).
Widget _mediaTerminalPanel({required Widget thumb, required Widget details}) {
  return IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        thumb,
        const SizedBox(width: 8),
        Expanded(child: details),
      ],
    ),
  );
}

/// Shown when the homeserver has no thumbnail (we no longer download the full file in the timeline).
Widget _timelineNoThumbnailRow({
  required ThemeData theme,
  required RoomMessageKind kind,
  required String ext,
  required String fileLabel,
  required String mediaMimetype,
  required BigInt mediaSizeBytes,
  required int mediaPreviewWidth,
  required int mediaPreviewHeight,
  required bool showTapHint,
}) {
  final icon = switch (kind) {
    RoomMessageKind.image => Icons.image_not_supported_outlined,
    RoomMessageKind.video => Icons.videocam_off_outlined,
    RoomMessageKind.file => _timelineFileIcon(ext),
    RoomMessageKind.poll => Icons.poll_outlined,
    _ => Icons.perm_media_outlined,
  };
  // Same frame as portrait timeline thumbnail ([_kTimelineThumbPortraitW] × [_kTimelineThumbPortraitH]).
  final placeholder = SizedBox(
    width: _kTimelineThumbPortraitW,
    height: _kTimelineThumbPortraitH,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.4),
      ),
      child: Icon(
        icon,
        size: 22,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
      ),
    ),
  );
  return _mediaTerminalPanel(
    thumb: placeholder,
    details: _mediaTerminalDetailsColumn(
      theme: theme,
      kind: kind,
      fileLabel: fileLabel,
      mediaMimetype: mediaMimetype,
      mediaSizeBytes: mediaSizeBytes,
      mediaPreviewWidth: mediaPreviewWidth,
      mediaPreviewHeight: mediaPreviewHeight,
      showTapHint: showTapHint,
    ),
  );
}

class _MessageMediaPreview extends StatefulWidget {
  const _MessageMediaPreview({
    required this.timelineMediaKey,
    required this.kind,
    required this.fileLabel,
    required this.caption,
    required this.mediaMimetype,
    required this.mediaSizeBytes,
    required this.mediaBlurhash,
    required this.mediaPreviewWidth,
    required this.mediaPreviewHeight,
    required this.loadMessageMedia,
    this.onOpen,
  });

  /// [Message.eventId] or, for local echoes, [Message.transactionId].
  final String timelineMediaKey;
  final RoomMessageKind kind;

  /// Filename / caption used for extension-based icons when there is no thumbnail.
  final String fileLabel;

  /// Matrix body text; shown when it adds information beyond [fileLabel] (e.g. real caption).
  final String caption;

  /// From event `info.mimetype` when present.
  final String mediaMimetype;

  /// From event `info.size` when present.
  final BigInt mediaSizeBytes;

  /// Matrix image/video `info` blurhash when present.
  final String mediaBlurhash;

  /// Known width/height for loading-frame aspect (thumbnail preferred in Rust).
  final int mediaPreviewWidth;
  final int mediaPreviewHeight;
  final Future<Uint8List?> Function(String eventId, {bool thumbnail})
  loadMessageMedia;
  final Future<void> Function()? onOpen;

  @override
  State<_MessageMediaPreview> createState() => _MessageMediaPreviewState();
}

class _MessageMediaPreviewState extends State<_MessageMediaPreview> {
  Uint8List? _bytes;
  _TimelinePreviewMeta? _previewMeta;
  bool _loading = true;
  String? _error;

  bool _captionRedundantWithFile(String caption) {
    final c = caption.trim();
    if (c.isEmpty) return true;
    final f = widget.fileLabel.trim();
    if (f.isEmpty) return false;
    return c == f || c == p.basename(f);
  }

  Widget? _extraCaption(ThemeData theme) {
    final c = widget.caption.trim();
    if (c.isEmpty || _captionRedundantWithFile(c)) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(c, style: theme.textTheme.bodyMedium),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.kind == RoomMessageKind.audio) {
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant _MessageMediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timelineMediaKey != widget.timelineMediaKey ||
        oldWidget.kind != widget.kind) {
      _bytes = null;
      _previewMeta = null;
      _error = null;
      if (widget.kind == RoomMessageKind.audio) {
        _loading = false;
      } else {
        _loading = true;
        _load();
      }
    }
  }

  Future<void> _load() async {
    try {
      var b = await widget.loadMessageMedia(
        widget.timelineMediaKey,
        thumbnail: true,
      );
      if (b != null && b.isNotEmpty && !_isTimelineRasterBytes(b)) {
        b = null;
      }
      _TimelinePreviewMeta? meta;
      if (b != null && b.isNotEmpty) {
        meta = await _timelineImagePreviewMeta(b);
        if (meta == null) b = null;
      }
      if (!mounted) return;
      setState(() {
        _bytes = b;
        _previewMeta = meta;
        _loading = false;
        if (b == null || b.isEmpty) {
          _error = 'Preview unavailable';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      final extra = _extraCaption(theme);
      // Match loaded layout: fixed frame + side info; blurhash or spinner in the thumb slot.
      final frame = _timelineLoadingThumbFrameSize(
        widget.mediaPreviewWidth,
        widget.mediaPreviewHeight,
      );
      final tw = frame.width;
      final th = frame.height;
      final scheme = theme.colorScheme;
      final blur = widget.mediaBlurhash.trim();
      final thumb = SizedBox(
        width: tw,
        height: th,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: scheme.surfaceContainerLow.withValues(alpha: 0.35),
          ),
          child: blur.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: BlurHash(hash: blur, imageFit: BoxFit.cover),
                )
              : Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  ),
                ),
        ),
      );
      final showHint = widget.onOpen != null;
      final panel = _mediaTerminalPanel(
        thumb: thumb,
        details: _mediaTerminalDetailsColumn(
          theme: theme,
          kind: widget.kind,
          fileLabel: widget.fileLabel,
          mediaMimetype: widget.mediaMimetype,
          mediaSizeBytes: widget.mediaSizeBytes,
          mediaPreviewWidth: widget.mediaPreviewWidth,
          mediaPreviewHeight: widget.mediaPreviewHeight,
          showTapHint: showHint,
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [panel, if (extra != null) extra],
      );
    }
    if (_error != null) {
      final row = _timelineNoThumbnailRow(
        theme: theme,
        kind: widget.kind,
        ext: _timelineExtLower(widget.fileLabel),
        fileLabel: widget.fileLabel,
        mediaMimetype: widget.mediaMimetype,
        mediaSizeBytes: widget.mediaSizeBytes,
        mediaPreviewWidth: widget.mediaPreviewWidth,
        mediaPreviewHeight: widget.mediaPreviewHeight,
        showTapHint: widget.onOpen != null,
      );
      final extra = _extraCaption(theme);
      return _maybeWrapOpen(
        extra != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [row, extra],
              )
            : row,
      );
    }
    if (widget.kind == RoomMessageKind.audio) {
      final audioThumb = SizedBox(
        width: _kTimelineThumbPortraitW,
        height: _kTimelineThumbPortraitH,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.4),
          ),
          child: Icon(
            Icons.audiotrack,
            color: theme.colorScheme.primary.withValues(alpha: 0.9),
            size: 22,
          ),
        ),
      );
      final row = _mediaTerminalPanel(
        thumb: audioThumb,
        details: _mediaTerminalDetailsColumn(
          theme: theme,
          kind: widget.kind,
          fileLabel: widget.fileLabel,
          mediaMimetype: widget.mediaMimetype,
          mediaSizeBytes: widget.mediaSizeBytes,
          mediaPreviewWidth: widget.mediaPreviewWidth,
          mediaPreviewHeight: widget.mediaPreviewHeight,
          showTapHint: widget.onOpen != null,
        ),
      );
      final audioCol = <Widget>[row];
      final extra = _extraCaption(theme);
      return _maybeWrapOpen(
        extra != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...audioCol, extra],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: audioCol,
              ),
      );
    }
    if (_bytes == null) return const SizedBox.shrink();
    final meta = _previewMeta;
    final preview = meta == null
        ? _timelineNoThumbnailRow(
            theme: theme,
            kind: widget.kind,
            ext: _timelineExtLower(widget.fileLabel),
            fileLabel: widget.fileLabel,
            mediaMimetype: widget.mediaMimetype,
            mediaSizeBytes: widget.mediaSizeBytes,
            mediaPreviewWidth: widget.mediaPreviewWidth,
            mediaPreviewHeight: widget.mediaPreviewHeight,
            showTapHint: widget.onOpen != null,
          )
        : _buildThumbnailWithSideInfo(theme, meta);
    final extra = _extraCaption(theme);
    return _maybeWrapOpen(
      extra != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [preview, extra],
            )
          : preview,
    );
  }

  /// Event thumbnail in a fixed frame; [Row] with metadata in [Expanded].
  Widget _buildThumbnailWithSideInfo(
    ThemeData theme,
    _TimelinePreviewMeta meta,
  ) {
    final oriented = _orientedIntrinsicForLayout(
      meta.rawSize,
      meta.exifOrientation,
    );
    final portrait = oriented.height > oriented.width;
    final tw = portrait ? _kTimelineThumbPortraitW : _kTimelineThumbLandscapeW;
    final th = portrait ? _kTimelineThumbPortraitH : _kTimelineThumbLandscapeH;
    Widget thumbDecodeError(_, Object __, StackTrace? ___) {
      return ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        child: Icon(
          Icons.broken_image_outlined,
          size: 22,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final turns = _exifQuarterTurns(meta.exifOrientation);
    final imageCore = turns == 0
        ? Image.memory(
            _bytes!,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: thumbDecodeError,
          )
        : RotatedBox(
            quarterTurns: turns,
            child: Image.memory(
              _bytes!,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: thumbDecodeError,
            ),
          );
    final thumb = SizedBox(
      width: tw,
      height: th,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              width: tw,
              height: th,
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                alignment: Alignment.center,
                child: imageCore,
              ),
            ),
          ),
          if (widget.kind == RoomMessageKind.video)
            IgnorePointer(
              child: Icon(
                Icons.play_circle_outline,
                size: portrait ? 18 : 20,
                color: theme.colorScheme.primary.withValues(alpha: 0.92),
              ),
            ),
        ],
      ),
    );
    return _mediaTerminalPanel(
      thumb: thumb,
      details: _mediaTerminalDetailsColumn(
        theme: theme,
        kind: widget.kind,
        fileLabel: widget.fileLabel,
        mediaMimetype: widget.mediaMimetype,
        mediaSizeBytes: widget.mediaSizeBytes,
        mediaPreviewWidth: widget.mediaPreviewWidth,
        mediaPreviewHeight: widget.mediaPreviewHeight,
        showTapHint: widget.onOpen != null,
      ),
    );
  }

  Widget _maybeWrapOpen(Widget child) {
    final open = widget.onOpen;
    if (open == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await open();
        },
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
