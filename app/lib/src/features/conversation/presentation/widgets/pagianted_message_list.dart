import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:linkify/linkify.dart' show linkify;
import 'package:path/path.dart' as p;
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/layout/conversation_message_style_preference.dart';
import 'package:provider/provider.dart';
import 'package:matrix/src/core/open_in_app_url.dart';
import 'package:matrix/src/features/conversation/presentation/widgets/audio_message_waveform.dart';
import 'package:matrix/src/core/timeline_local_hidden_store.dart';
import 'package:matrix/src/core/timeline_raster_thumb.dart';
import 'package:matrix/src/features/settings/domain/profile_prefs.dart';
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

/// Bold highlight for in-conversation search matches (merged onto base text style).
TextStyle _timelineSearchHighlightStyle(ColorScheme scheme) => TextStyle(
      backgroundColor: scheme.tertiaryContainer.withValues(alpha: 0.92),
      color: scheme.onTertiaryContainer,
      fontWeight: FontWeight.w700,
    );

List<TextSpan> _plainTextSearchHighlightSpans(
  String text,
  String? highlightQuery,
  TextStyle? baseStyle,
  TextStyle highlightStyle,
) {
  final q = highlightQuery?.trim();
  if (q == null || q.isEmpty) {
    return [TextSpan(text: text, style: baseStyle)];
  }
  final pattern = RegExp(RegExp.escape(q), caseSensitive: false);
  final out = <TextSpan>[];
  var start = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > start) {
      out.add(TextSpan(text: text.substring(start, m.start), style: baseStyle));
    }
    out.add(
      TextSpan(
        text: text.substring(m.start, m.end),
        style: baseStyle?.merge(highlightStyle) ?? highlightStyle,
      ),
    );
    start = m.end;
  }
  if (start < text.length) {
    out.add(TextSpan(text: text.substring(start), style: baseStyle));
  }
  return out;
}

List<InlineSpan> _linkifySpansWithSearchHighlight(
  String text,
  String? highlightQuery,
  TextStyle? baseStyle,
  TextStyle? linkStyle,
  TextStyle highlightStyle,
  LinkCallback? onOpen, {
  bool useMouseRegion = false,
}) {
  final q = highlightQuery?.trim();
  final elements = linkify(text);
  final spans = <InlineSpan>[];
  for (final element in elements) {
    if (element is LinkableElement) {
      spans.add(
        TextSpan(
          text: element.text,
          style: linkStyle,
          recognizer: onOpen != null
              ? (TapGestureRecognizer()..onTap = () => onOpen(element))
              : null,
          mouseCursor: useMouseRegion ? SystemMouseCursors.click : null,
        ),
      );
    } else {
      final t = element.text;
      if (q == null || q.isEmpty) {
        spans.add(TextSpan(text: t, style: baseStyle));
      } else {
        spans.addAll(
          _plainTextSearchHighlightSpans(t, q, baseStyle, highlightStyle),
        );
      }
    }
  }
  return spans;
}

bool _conversationPlacementLeftRight(BuildContext context) {
  try {
    return conversationUsesLeftRightPlacement(
      Provider.of<ConversationMessageStyleNotifier>(context, listen: true).value,
    );
  } catch (_) {
    return true;
  }
}

/// Local “delete for me” — message still exists for others; hidden on this device only.
Widget _timelineRemovedOnDeviceBubbleBody(
  BuildContext context,
  Color accentColor,
  bool isOutgoing, {
  bool placementLeftRight = true,
}) {
  final theme = Theme.of(context);
  final muted = theme.colorScheme.onSurfaceVariant;
  const titleSize = 12.5;
  const subSize = 11.5;
  final layoutOutgoing = placementLeftRight && isOutgoing;
  final align =
      layoutOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start;
  final textAlign = layoutOutgoing ? TextAlign.end : TextAlign.start;
  final icon = Icon(
    Icons.visibility_off_outlined,
    size: 18,
    color: accentColor.withValues(alpha: 0.92),
  );
  final textBlock = Expanded(
    child: Column(
      crossAxisAlignment: align,
      children: [
        Text(
          'Message removed',
          textAlign: textAlign,
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
          textAlign: textAlign,
          style: theme.textTheme.bodySmall?.copyWith(
            color: muted,
            fontStyle: FontStyle.italic,
            height: 1.3,
            fontSize: subSize,
          ),
        ),
      ],
    ),
  );
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: layoutOutgoing
        ? [textBlock, const SizedBox(width: 8), icon]
        : [icon, const SizedBox(width: 8), textBlock],
  );
}

/// Full-width deleted state inside a message bubble (redacted event).
Widget _timelineDeletedBubbleBody(
  BuildContext context,
  Color accentColor,
  bool isOutgoing, {
  bool placementLeftRight = true,
}) {
  final theme = Theme.of(context);
  final muted = theme.colorScheme.onSurfaceVariant;
  const titleSize = 12.5;
  const subSize = 11.5;
  final layoutOutgoing = placementLeftRight && isOutgoing;
  final align =
      layoutOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start;
  final textAlign = layoutOutgoing ? TextAlign.end : TextAlign.start;
  final icon = Icon(
    Icons.chat_bubble_outline,
    size: 18,
    color: accentColor.withValues(alpha: 0.92),
  );
  final textBlock = Expanded(
    child: Column(
      crossAxisAlignment: align,
      children: [
        Text(
          'Deleted message',
          textAlign: textAlign,
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
          textAlign: textAlign,
          style: theme.textTheme.bodySmall?.copyWith(
            color: muted,
            fontStyle: FontStyle.italic,
            height: 1.3,
            fontSize: subSize,
          ),
        ),
      ],
    ),
  );
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: layoutOutgoing
        ? [textBlock, const SizedBox(width: 8), icon]
        : [icon, const SizedBox(width: 8), textBlock],
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
}) async {
  // Desktop used showMenu with a zero-size RelativeRect (L==R, T==B), which
  // collapsed the menu to a single vertical column on Windows. Use the same
  // Wrap + grid panel as mobile via showAdaptivePanel (dialog on wide desktop).
  await showAdaptivePanel<void>(
    context: context,
    scrollControlled: true,
    builder: (ctx) => Material(
      color: MatrixTheme.terminalBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: MatrixTheme.terminalBorder),
      ),
      child: _QuickReactionBottomSheet(
        onPick: (key) => onToggle(key),
      ),
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

String _dateDividerLabel(BuildContext context, BigInt timestampMs) {
  int ms;
  try {
    ms = timestampMs.toInt();
  } catch (_) {
    return '';
  }
  if (ms <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(dt.year, dt.month, dt.day);
  if (d == today) return 'Today';
  if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
  final loc = MaterialLocalizations.of(context);
  return loc.formatFullDate(dt);
}

class _TimelineDateDividerRow extends StatelessWidget {
  const _TimelineDateDividerRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final lineColor = muted.withValues(alpha: 0.35);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, thickness: 1, color: lineColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: muted,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.35,
              ),
            ),
          ),
          Expanded(child: Divider(height: 1, thickness: 1, color: lineColor)),
        ],
      ),
    );
  }
}

class _TimelineSystemEventRow extends StatelessWidget {
  const _TimelineSystemEventRow({
    required this.text,
    this.searchHighlightQuery,
  });

  final String text;
  final String? searchHighlightQuery;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: muted.withValues(alpha: 0.92),
      fontStyle: FontStyle.italic,
      height: 1.25,
    );
    final hl = _timelineSearchHighlightStyle(theme.colorScheme);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
      child: Center(
        child: SelectableText.rich(
          TextSpan(
            children: _plainTextSearchHighlightSpans(
              text,
              searchHighlightQuery,
              baseStyle,
              hl,
            ),
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _TimelineUnreadMarkerRow extends StatelessWidget {
  const _TimelineUnreadMarkerRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: accent.withValues(alpha: 0.45),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'NEW MESSAGES',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: accent.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// MatrixRTC / legacy VoIP row: icon + label inside the normal message bubble chrome.
class _CallTimelineBubbleBody extends StatelessWidget {
  const _CallTimelineBubbleBody({
    required this.label,
    required this.accent,
  });

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.call_rounded, size: 22, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

/// Return `true` if this failure was shown elsewhere (suppresses the snack bar).
typedef ProgrammaticJumpFailureHandler = bool Function(String message);

class PaginatedMessageList extends StatefulWidget {
  const PaginatedMessageList({
    super.key,
    required this.roomId,
    this.senderAvatarMxcByUserId,
    required this.loadMessageMedia,
    required this.loadSenderAvatar,
    required this.initialMessages, // List<Message> ordered oldest → newest
    required this.loadOlder, // Future<LoadOlderResult> Function(Message oldest)
    this.onRetryFailedSend,
    required this.onVisibleRange, // Optional: for read receipts
    this.onOpenAttachment,
    this.jumpToEventNotifier,
    /// When set, may handle jump failures (e.g. in-conversation search inline UI).
    this.onProgrammaticJumpFailure,
    /// Increment (e.g. after sending) to scroll to the latest messages even when
    /// the user was scrolled up.
    this.scrollToLatestNotifier,
    this.isGroupRoom = false,
    required this.onToggleReaction,
    required this.onShowReactionReactors,
    this.onPollVote,
    this.onShowMessageActions,
    this.onBecameAtBottom,
    this.onLeftNewestEdge,
    this.onSenderAvatarTap,
    /// When non-empty, matching substrings in message bodies (and system rows) are highlighted.
    this.timelineSearchHighlightQuery,
  });

  final ProgrammaticJumpFailureHandler? onProgrammaticJumpFailure;

  final String roomId;

  /// Active in-conversation search phrase for inline highlights (case-insensitive).
  final String? timelineSearchHighlightQuery;

  /// Live member avatars from room state; when non-null, overrides stale [Message.senderAvatarMxc].
  final ValueNotifier<Map<String, String>>? senderAvatarMxcByUserId;

  final Future<Uint8List?> Function(String eventId, {bool thumbnail})
  loadMessageMedia;

  /// Decoded JPEG/PNG (etc.) for a profile `mxc://` URI; return null on failure.
  final Future<Uint8List?> Function(String mxcUri) loadSenderAvatar;

  /// Opens full attachment in the in-app viewer (or external app for office files).
  final Future<void> Function(Message message)? onOpenAttachment;
  final List<Message> initialMessages;
  final Future<LoadOlderResult> Function(Message oldest) loadOlder;
  final Future<void> Function(String transactionId)? onRetryFailedSend;
  final void Function(Message firstVisible, Message lastVisible)?
  onVisibleRange;

  /// Fires when the user scrolls from higher up back to the latest messages (reverse list “bottom”).
  /// Use to send read receipts without waiting for the next timeline sync.
  final VoidCallback? onBecameAtBottom;

  /// Fires when the user leaves the newest-message edge (scrolls up). Cancels debounced mark-read.
  final VoidCallback? onLeftNewestEdge;

  /// When set to a non-empty event id (e.g. from room info), scrolls that bubble into view.
  final ValueNotifier<String?>? jumpToEventNotifier;

  /// Bumped after a successful send so the list catches up to the latest tail.
  final ValueNotifier<int>? scrollToLatestNotifier;

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

  /// ⋮ menu: reply, react, delete, … [anchorGlobal] is the ⋮ button for desktop [showMenu].
  final void Function(BuildContext context, Message message, Offset anchorGlobal)?
  onShowMessageActions;

  /// Tap on the inline sender avatar (timeline header): profile / DM entry point.
  final void Function(BuildContext context, Message message)? onSenderAvatarTap;

  @override
  State<PaginatedMessageList> createState() => PaginatedMessageListState();
}

class PaginatedMessageListState extends State<PaginatedMessageList> {
  /// Avoid PageStorage restoring a stale offset when the timeline list rebuilds
  /// after pagination (same [ScrollPosition] can otherwise snap wrong).
  final _controller = ScrollController(keepScrollOffset: false);
  final GlobalKey _historyScrollAnchorKey =
      GlobalKey(debugLabel: 'timelineHistoryAnchor');
  bool _scrollListenerAttached = false;
  bool _isLoadingOlder = false;
  bool _hasMore = true;
  /// When set, the matching row uses [_historyScrollAnchorKey] for [Scrollable.ensureVisible].
  String? _pendingHistoryScrollStableKey;
  /// Skips tail-driven [_scrollToBottom] right after a history page (avoids fighting restore).
  bool _deferTailAutoscroll = false;
  int _unseenNewCount = 0;
  /// When the timeline has no read marker, oldest unread from stream tail growth (scroll-up).
  String? _firstStreamUnreadEventId;
  /// Seeded true so we do not fire [onBecameAtBottom] on the initial layout-at-bottom frame.
  bool _wasAtBottom = true;
  /// Drives the jump-to-latest chip; must update via [setState] because [ScrollController] does not.
  bool _showJumpToLatestFab = false;
  String _lastTailKey = '';
  String? _pendingJumpEventId;
  GlobalKey? _jumpKey;
  int _jumpRetryFrames = 0;
  int _jumpResolveGeneration = 0;

  /// Fires [onBecameAtBottom] once when the list is first laid out at the newest edge.
  bool _notifiedInitialBottomRead = false;
  int? _lastScrollToLatestSeq;

  /// Event / transaction id to frame after a successful jump-to-message.
  String? _jumpHighlightId;
  Timer? _jumpHighlightTimer;

  /// Avoid O(n) [List.reversed] / allocation on every rebuild when the source list is unchanged.
  List<Message>? _newestFirstDisplayCache;
  List<Message>? _newestFirstCacheSourceRef;
  int _newestFirstCacheLength = -1;
  bool? _newestFirstCacheIsGroupRoom;

  static const Duration _jumpHighlightDuration = Duration(seconds: 3);

  /// Direct rooms: hide noisy `m.room.member` "joined the room" rows (matches Rust timeline copy).
  static bool _isDirectRoomHiddenMemberJoin(Message m) {
    if (m.messageType != MessageType.membershipChange) return false;
    return m.content.endsWith(' joined the room');
  }

  List<Message> _newestFirstDisplay() {
    final src = widget.initialMessages;
    if (_newestFirstDisplayCache != null &&
        identical(_newestFirstCacheSourceRef, src) &&
        _newestFirstCacheLength == src.length &&
        _newestFirstCacheIsGroupRoom == widget.isGroupRoom) {
      return _newestFirstDisplayCache!;
    }
    _newestFirstCacheSourceRef = src;
    _newestFirstCacheLength = src.length;
    _newestFirstCacheIsGroupRoom = widget.isGroupRoom;
    var rev = src.reversed.toList(growable: false);
    if (!widget.isGroupRoom) {
      rev = rev
          .where((m) => !_isDirectRoomHiddenMemberJoin(m))
          .toList(growable: false);
    }
    _newestFirstDisplayCache = rev;
    return _newestFirstDisplayCache!;
  }

  /// Sync after layout / programmatic scroll so [_wasAtBottom] matches the real offset before any
  /// user drag (listener may not run until the position changes).
  void _syncWasAtBottomBaseline() {
    if (!_controller.hasClients) return;
    _wasAtBottom = _isAtBottom;
  }

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

  void _presentProgrammaticJumpFailure(String message) {
    if (widget.onProgrammaticJumpFailure != null &&
        widget.onProgrammaticJumpFailure!(message)) {
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool get _isAtBottom {
    // With reverse:true, “newest” edge is a small pixel offset; use a looser band
    // so read receipts still fire if padding rounds [pixels] slightly above 0.
    return !_controller.hasClients || _controller.position.pixels <= 56;
  }

  void _maybeNotifyReadAtBottom() {
    if (_notifiedInitialBottomRead) return;
    if (!_controller.hasClients) return;
    if (!_isAtBottom) return;
    _notifiedInitialBottomRead = true;
    widget.onBecameAtBottom?.call();
  }

  void _syncJumpFabVisibility() {
    if (!mounted) return;
    final show = !_isAtBottom;
    if (show != _showJumpToLatestFab) {
      setState(() => _showJumpToLatestFab = show);
    }
  }

  void _onScrollToLatestNotifier() {
    final n = widget.scrollToLatestNotifier?.value;
    if (n == null) return;
    if (_lastScrollToLatestSeq == n) return;
    _lastScrollToLatestSeq = n;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToBottom();
    });
  }

  @override
  void initState() {
    super.initState();
    _lastScrollToLatestSeq = widget.scrollToLatestNotifier?.value;
    widget.scrollToLatestNotifier?.addListener(_onScrollToLatestNotifier);
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
        _syncJumpFabVisibility();
        _syncWasAtBottomBaseline();
        _maybeNotifyReadAtBottom();
        // Scroll [ScrollPosition] may attach one frame later than first layout.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _syncWasAtBottomBaseline();
          _maybeNotifyReadAtBottom();
        });
      });
    }
  }

  @override
  void dispose() {
    _jumpHighlightTimer?.cancel();
    if (_controller.hasClients && _isAtBottom) {
      widget.onBecameAtBottom?.call();
    }
    widget.scrollToLatestNotifier?.removeListener(_onScrollToLatestNotifier);
    widget.jumpToEventNotifier?.removeListener(_onJumpNotifier);
    if (_scrollListenerAttached) {
      _controller.removeListener(_onScroll);
    }
    _deferTailAutoscroll = false;
    _pendingHistoryScrollStableKey = null;
    _controller.dispose();
    super.dispose();
  }

  /// Prefer [Message.transactionId] so local echoes keep the same [ValueKey] when
  /// [eventId] arrives; avoids bubble teardown/rebuild and scroll flicker.
  String _stableMessageKey(Message m) {
    if (m.transactionId.isNotEmpty) return 't:${m.transactionId}';
    if (m.eventId.isNotEmpty) return 'e:${m.eventId}';
    return 'x:${m.timestamp}:${m.content.hashCode}';
  }

  bool _listPrefixEqual(List<Message> a, List<Message> b, int n) {
    if (n < 0 || n > a.length || n > b.length) return false;
    for (var i = 0; i < n; i++) {
      if (_stableMessageKey(a[i]) != _stableMessageKey(b[i])) return false;
    }
    return true;
  }

  /// New messages only at the end (oldest → newest storage).
  bool _didAppendOnlyAtTail(List<Message> oldL, List<Message> newL) {
    final o = oldL.length;
    final n = newL.length;
    if (n <= o) return false;
    return _listPrefixEqual(oldL, newL, o);
  }

  /// Older history only at the start (full list replace from sync / pagination).
  bool _didPrependOnlyAtHead(List<Message> oldL, List<Message> newL) {
    final o = oldL.length;
    final n = newL.length;
    if (n <= o) return false;
    for (var i = 0; i < o; i++) {
      if (_stableMessageKey(newL[n - o + i]) != _stableMessageKey(oldL[i])) {
        return false;
      }
    }
    return true;
  }

  int? _readMarkerDisplayIndex(List<Message> newestFirst) {
    for (var i = 0; i < newestFirst.length; i++) {
      if (newestFirst[i].messageType == MessageType.readMarker) return i;
    }
    return null;
  }

  int _unreadCountFromReadMarker(List<Message> newestFirst, int readMarkerIndex) {
    var c = 0;
    for (var i = 0; i < readMarkerIndex; i++) {
      if (_countsTowardUnreadFab(newestFirst[i])) c++;
    }
    return c;
  }

  int _fabUnreadCountForDisplay(List<Message> newestFirst) {
    // At the newest edge the user has caught up visually; badge must clear even
    // if the read-marker row in the timeline has not synced yet.
    if (_controller.hasClients && _isAtBottom) return 0;
    final rm = _readMarkerDisplayIndex(newestFirst);
    if (rm != null) return _unreadCountFromReadMarker(newestFirst, rm);
    return _unseenNewCount;
  }

  void _onJumpDownFabTapped() {
    // Always go to the true newest edge so [_isAtBottom] becomes true, stream
    // unread state clears, and [onBecameAtBottom] runs (read receipt). Jumping
    // only to “first unread” left the viewport above the tail so the FAB count
    // (read-marker–derived) never dropped.
    _scrollToBottom();
  }

  /// Pins the row that was chronologically oldest before a prepend (same logical
  /// event still exists after load). More reliable than extent math alone for
  /// [CustomScrollView] + [SliverList.builder] + [reverse].
  void _scheduleHistoryAnchorEnsureVisible({int maxAttempts = 10}) {
    void attempt(int n) {
      if (!mounted || _pendingHistoryScrollStableKey == null) return;
      if (n >= maxAttempts) {
        _pendingHistoryScrollStableKey = null;
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = _historyScrollAnchorKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: Duration.zero,
            curve: Curves.linear,
            alignment: 1,
          );
          _pendingHistoryScrollStableKey = null;
          return;
        }
        attempt(n + 1);
      });
    }

    attempt(0);
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
    // Present before clearing [jumpToEventNotifier] so listeners can still
    // attribute the failure (e.g. in-conversation search vs date jump).
    if (mounted) {
      _presentProgrammaticJumpFailure(message);
    }
    widget.jumpToEventNotifier?.value = null;
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
        MessageType.membershipChange,
        MessageType.profileChange,
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
        _syncWasAtBottomBaseline();
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

    final display = _newestFirstDisplay();
    final idx = _jumpTargetDisplayIndex(id, display);
    if (idx == null) {
      if (mounted) {
        _presentProgrammaticJumpFailure(
          'That message is not shown as a row in this timeline.',
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
      _presentProgrammaticJumpFailure('Could not scroll to that message.');
    }
    _jumpRetryFrames = 0;
    setState(() {
      _pendingJumpEventId = null;
      _jumpKey = null;
    });
    widget.jumpToEventNotifier?.value = null;
  }

  static const double _loadOlderThresholdPx = 80;

  /// Slightly looser than [_loadOlderThresholdPx] so we still restore scroll if
  /// layout rounds [pixels] just below the load-more zone.
  static const double _scrollPreserveLeadPx = 160;

  void _onScroll() {
    if (!_controller.hasClients) return;
    // Load older when scrolled near top (reverse:true so top = maxScrollExtent)
    final pos = _controller.position;
    if (pos.pixels >= pos.maxScrollExtent - _loadOlderThresholdPx) {
      _maybeLoadOlder();
    }

    final atBottom = _isAtBottom;
    if (atBottom && !_wasAtBottom) {
      widget.onBecameAtBottom?.call();
    } else if (!atBottom && _wasAtBottom) {
      widget.onLeftNewestEdge?.call();
    }
    _wasAtBottom = atBottom;

    widget.onVisibleRange?.call(_firstVisible(), _lastVisible());
    _syncJumpFabVisibility();
  }

  @override
  void didUpdateWidget(PaginatedMessageList oldWidget) {
    final oldList = oldWidget.initialMessages;
    final newList = widget.initialMessages;
    final wasAtBottom = _isAtBottom;
    double? scrollPreserveOldPixels;
    double? scrollPreserveOldMax;
    final appendedTail = _didAppendOnlyAtTail(oldList, newList);
    final prependedHead =
        !appendedTail && _didPrependOnlyAtHead(oldList, newList);
    if ((appendedTail || prependedHead) &&
        !wasAtBottom &&
        _controller.hasClients) {
      scrollPreserveOldPixels = _controller.position.pixels;
      scrollPreserveOldMax = _controller.position.maxScrollExtent;
    }

    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollToLatestNotifier != widget.scrollToLatestNotifier) {
      oldWidget.scrollToLatestNotifier?.removeListener(_onScrollToLatestNotifier);
      widget.scrollToLatestNotifier?.addListener(_onScrollToLatestNotifier);
      _lastScrollToLatestSeq = widget.scrollToLatestNotifier?.value;
    }
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
    if (newTail.isNotEmpty &&
        newTail != _lastTailKey &&
        _isAtBottom &&
        !_deferTailAutoscroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom();
      });
    }
    _lastTailKey = newTail;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (scrollPreserveOldPixels != null &&
          scrollPreserveOldMax != null &&
          _controller.hasClients) {
        final newMax = _controller.position.maxScrollExtent;
        final delta = newMax - scrollPreserveOldMax;
        if (delta.abs() > 0.5) {
          _controller.jumpTo(
            (scrollPreserveOldPixels + delta).clamp(0.0, newMax),
          );
        }
      }
      if (!mounted) return;
      if (appendedTail && !wasAtBottom && oldList.isNotEmpty) {
        final preview = newList.reversed.toList(growable: false);
        if (_readMarkerDisplayIndex(preview) == null) {
          final oldLen = oldList.length;
          var addedUnread = 0;
          for (var i = oldLen; i < newList.length; i++) {
            if (_countsTowardUnreadFab(newList[i])) addedUnread++;
          }
          if (addedUnread > 0) {
            final firstNew = newList[oldLen];
            final fid = firstNew.eventId.isNotEmpty
                ? firstNew.eventId
                : firstNew.transactionId;
            setState(() {
              _unseenNewCount += addedUnread;
              if (fid.isNotEmpty) {
                _firstStreamUnreadEventId ??= fid;
              }
            });
          }
        }
      }
      if (!mounted) return;
      _syncJumpFabVisibility();
      _maybeNotifyReadAtBottom();
    });
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

    // Parent may push a longer timeline while we await; block tail autoscroll
    // until after layout so a transient `_isAtBottom` does not call [_scrollToBottom].
    _deferTailAutoscroll = true;

    final posBeforeLoad =
        _controller.hasClients ? _controller.position : null;
    _pendingHistoryScrollStableKey = null;
    var preserveHistoryScroll = false;
    if (posBeforeLoad != null) {
      final max = posBeforeLoad.maxScrollExtent;
      final px = posBeforeLoad.pixels;
      // Require real scroll range and that we're not at the newest edge (px≈0),
      // otherwise `px >= max - lead` is true for tiny lists and we'd yank the view.
      if (max > 32 &&
          px > 24 &&
          px >= max - _scrollPreserveLeadPx) {
        preserveHistoryScroll = true;
        _pendingHistoryScrollStableKey =
            _stableMessageKey(widget.initialMessages.first);
      }
    }

    try {
      setState(() => _isLoadingOlder = true);

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

      if (preserveHistoryScroll) {
        _scheduleHistoryAnchorEnsureVisible();
      }
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _deferTailAutoscroll = false;
        });
      });
    }
  }

  // Call this when a brand-new message arrives (push from server)
  void addIncoming(Message m) {
    final shouldAutoscroll = _isAtBottom;
    setState(() => widget.initialMessages.add(m));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (shouldAutoscroll) {
        _scrollToBottom();
      } else {
        final fid = m.eventId.isNotEmpty ? m.eventId : m.transactionId;
        setState(() {
          if (_countsTowardUnreadFab(m)) {
            _unseenNewCount += 1;
            if (fid.isNotEmpty) {
              _firstStreamUnreadEventId ??= fid;
            }
          }
        });
      }
    });
  }

  void _scrollToBottom() {
    if (!_controller.hasClients) return;
    setState(() {
      _unseenNewCount = 0;
      _firstStreamUnreadEventId = null;
    });
    _controller
        .animateTo(
      0, // because reverse:true
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    )
        .then((_) {
      if (mounted) {
        _syncWasAtBottomBaseline();
        _syncJumpFabVisibility();
      }
    });
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

    final display = _newestFirstDisplay();
    final fabUnread = _fabUnreadCountForDisplay(display);
    final messagePlacementLR = _conversationPlacementLeftRight(context);

    return Stack(
      children: [
        NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            if (_isAtBottom) {
              widget.onBecameAtBottom?.call();
              if (_unseenNewCount != 0 || _firstStreamUnreadEventId != null) {
                setState(() {
                  _unseenNewCount = 0;
                  _firstStreamUnreadEventId = null;
                });
              }
            }
            return false;
          },
          child: CustomScrollView(
            controller: _controller,
            reverse: true,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverList.builder(
                itemCount: display.length,
                itemBuilder: (context, index) {
                  final message = display[index];

                  // Virtual rows: date / read-marker UI; timeline start is invisible.
                  if (message.messageType == MessageType.timelineStart) {
                    return const SizedBox.shrink();
                  }
                  if (message.messageType == MessageType.dateDivider) {
                    return _TimelineDateDividerRow(
                      label: _dateDividerLabel(context, message.timestamp),
                    );
                  }
                  if (message.messageType == MessageType.readMarker) {
                    return const _TimelineUnreadMarkerRow();
                  }
                  if (message.messageType == MessageType.membershipChange ||
                      message.messageType == MessageType.profileChange) {
                    final stableSys = _stableMessageKey(message);
                    return KeyedSubtree(
                      key: ValueKey<String>(stableSys),
                      child: _TimelineSystemEventRow(
                        text: message.content,
                        searchHighlightQuery: widget.timelineSearchHighlightQuery,
                      ),
                    );
                  }
                  // Real [MessageType.message] can have empty [content] (e.g. image/file
                  // with no caption); those must still build so jump-to-event GlobalKeys attach.
                  // Redacted events also have empty body — must build so the deleted placeholder shows.
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
                  final stable = _stableMessageKey(message);
                  final historyAnchor = _pendingHistoryScrollStableKey != null &&
                      stable == _pendingHistoryScrollStableKey;
                  final subtreeKey = useJumpKey
                      ? jumpKey
                      : historyAnchor
                          ? _historyScrollAnchorKey
                          : ValueKey(stable);
                  return KeyedSubtree(
                    key: subtreeKey,
                    child: ListenableBuilder(
                      listenable: ProfilePrefs.instance,
                      builder: (context, _) {
                        return _buildMessageBubble(
                          message,
                          index: index,
                          roomId: widget.roomId,
                          messagePlacementLeftRight: messagePlacementLR,
                          senderAvatarMxcByUserId:
                              widget.senderAvatarMxcByUserId,
                          loadMessageMedia: widget.loadMessageMedia,
                          loadSenderAvatar: widget.loadSenderAvatar,
                          ownProfileInitials:
                              ProfilePrefs.instance.initialsOverride,
                          ownAvatarMxcFallback:
                              ProfilePrefs.instance.ownAvatarMxc,
                          onOpenAttachment: widget.onOpenAttachment,
                          jumpToEventNotifier: widget.jumpToEventNotifier,
                          isGroupRoom: widget.isGroupRoom,
                          onToggleReaction: widget.onToggleReaction,
                          onShowReactionReactors:
                              widget.onShowReactionReactors,
                          onPollVote: widget.onPollVote,
                          onSenderAvatarTap: widget.onSenderAvatarTap,
                          searchHighlightQuery:
                              widget.timelineSearchHighlightQuery,
                          jumpHighlighted:
                              _jumpHighlightId != null &&
                              _messageMatchesJumpTarget(
                                message,
                                _jumpHighlightId!,
                              ),
                        );
                      },
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

        // Jump to latest (always when scrolled up; subtitle when there are new messages).
        if (_showJumpToLatestFab)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                elevation: 2,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  onTap: _onJumpDownFabTapped,
                  borderRadius: BorderRadius.circular(22),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Badge(
                          isLabelVisible: fabUnread > 0,
                          label: Text(
                            fabUnread > 99 ? '99+' : '$fabUnread',
                            style: const TextStyle(fontSize: 10),
                          ),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 22,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        if (fabUnread > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '$fabUnread unread ${fabUnread == 1 ? "message" : "messages"}',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ],
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
    required String roomId,
    required bool messagePlacementLeftRight,
    ValueNotifier<Map<String, String>>? senderAvatarMxcByUserId,
    required Future<Uint8List?> Function(String eventId, {bool thumbnail})
    loadMessageMedia,
    required Future<Uint8List?> Function(String mxcUri) loadSenderAvatar,
    String? ownProfileInitials,
    String? ownAvatarMxcFallback,
    Future<void> Function(Message message)? onOpenAttachment,
    ValueNotifier<String?>? jumpToEventNotifier,
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
    void Function(BuildContext context, Message message)? onSenderAvatarTap,
    bool jumpHighlighted = false,
    String? searchHighlightQuery,
  }) {
    Widget bubbleForMap(Map<String, String>? avatarMap) => MessageBubble(
          message: m,
          roomId: roomId,
          isOutgoing: m.isOwn,
          messagePlacementLeftRight: messagePlacementLeftRight,
          loadMessageMedia: loadMessageMedia,
          loadSenderAvatar: loadSenderAvatar,
          ownProfileInitials: ownProfileInitials,
          ownAvatarMxcFallback: ownAvatarMxcFallback,
          senderAvatarMxcByUserId: avatarMap,
          onRetryFailedSend: widget.onRetryFailedSend,
          onOpenAttachment: onOpenAttachment,
          jumpToEventNotifier: jumpToEventNotifier,
          isGroupRoom: isGroupRoom,
          onToggleReaction: onToggleReaction,
          onShowReactionReactors: onShowReactionReactors,
          onPollVote: onPollVote,
          onOpenMessageActions: widget.onShowMessageActions != null
              ? (ctx, anchor) => widget.onShowMessageActions!(ctx, m, anchor)
              : null,
          onSenderAvatarTap: onSenderAvatarTap,
          searchHighlightQuery: searchHighlightQuery,
        );
    final Widget bubble = senderAvatarMxcByUserId != null
        ? ValueListenableBuilder<Map<String, String>>(
            valueListenable: senderAvatarMxcByUserId,
            builder: (context, map, _) => bubbleForMap(map),
          )
        : bubbleForMap(null);
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

const double _kMessageAvatarSize = 30;

/// Initials for timeline avatar fallback (display name or Matrix user id localpart).
/// [ownInitialsOverride] applies to your own messages from profile account data.
String _timelineMessageInitials(
  Message message, {
  String? ownInitialsOverride,
}) {
  if (message.isOwn &&
      ownInitialsOverride != null &&
      ownInitialsOverride.trim().isNotEmpty) {
    final t = ownInitialsOverride.trim().toUpperCase();
    return t.length <= 2 ? t : t.substring(0, 2);
  }
  final raw = message.sender.trim();
  if (raw.isEmpty) {
    final uid = message.senderUserId.trim();
    if (uid.length > 1 && uid.startsWith('@')) {
      final colon = uid.indexOf(':', 1);
      final end = colon > 0 ? colon : uid.length;
      final lp = uid.substring(1, end);
      if (lp.isEmpty) return '?';
      return lp.length >= 2
          ? lp.substring(0, 2).toUpperCase()
          : lp[0].toUpperCase();
    }
    return '?';
  }
  final parts = raw.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.length >= 2 &&
      parts[0].isNotEmpty &&
      parts[1].isNotEmpty) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  if (raw.length >= 2) return raw.substring(0, 2).toUpperCase();
  return raw[0].toUpperCase();
}

/// Timeline often omits [Message.senderAvatarMxc] for the local user until `m.room.member` syncs.
/// Prefer [senderAvatarMxcByUserId] when set so avatar changes apply to existing bubbles.
String _effectiveTimelineAvatarMxc(
  Message message,
  String? ownAvatarMxcFallback, {
  Map<String, String>? senderAvatarMxcByUserId,
}) {
  final uid = message.senderUserId.trim();
  if (uid.isNotEmpty && senderAvatarMxcByUserId != null) {
    final live = senderAvatarMxcByUserId[uid]?.trim() ?? '';
    if (live.isNotEmpty) return live;
  }
  final t = message.senderAvatarMxc.trim();
  if (t.isNotEmpty) return t;
  if (message.isOwn) {
    final o = ownAvatarMxcFallback?.trim() ?? '';
    if (o.isNotEmpty) return o;
  }
  return '';
}

class _MessageSenderAvatar extends StatefulWidget {
  const _MessageSenderAvatar({
    required this.mxcUri,
    required this.initials,
    required this.isOutgoing,
    required this.loadBytes,
    this.onTap,
  });

  final String mxcUri;
  final String initials;
  final bool isOutgoing;
  final Future<Uint8List?> Function(String mxc) loadBytes;
  final VoidCallback? onTap;

  @override
  State<_MessageSenderAvatar> createState() => _MessageSenderAvatarState();
}

class _MessageSenderAvatarState extends State<_MessageSenderAvatar> {
  static final Map<String, Uint8List> _bytesCache = {};
  Future<Uint8List?>? _loadFuture;

  @override
  void initState() {
    super.initState();
    _syncFuture();
  }

  @override
  void didUpdateWidget(covariant _MessageSenderAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mxcUri != widget.mxcUri ||
        oldWidget.loadBytes != widget.loadBytes) {
      _syncFuture();
      setState(() {});
    }
  }

  void _syncFuture() {
    final m = widget.mxcUri.trim();
    if (m.isEmpty) {
      _loadFuture = null;
      return;
    }
    final hit = _bytesCache[m];
    if (hit != null) {
      _loadFuture = Future<Uint8List?>.value(hit);
      return;
    }
    _loadFuture = widget.loadBytes(m).then((b) async {
      if (b == null || b.isEmpty) return b;
      final e = timelineThumbDecodeExtentPx(_kMessageAvatarSize);
      final small = await encodeRasterPngFitBox(
        b,
        targetWidthPx: e,
        targetHeightPx: e,
      );
      final out = small ?? b;
      _bytesCache[m] = out;
      return out;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = Border.all(
      color: MatrixTheme.terminalBorder.withValues(alpha: 0.9),
      width: 1,
    );
    final bg = widget.isOutgoing
        ? theme.colorScheme.primary.withValues(alpha: 0.2)
        : MatrixTheme.matrixDarkGreen.withValues(alpha: 0.55);
    final fg = widget.isOutgoing
        ? theme.colorScheme.primary
        : MatrixTheme.matrixLightGreen;
    final initials = widget.initials.isNotEmpty ? widget.initials : '?';

    Widget wrapInteractive(Widget child) {
      final t = widget.onTap;
      if (t == null) return child;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Tooltip(
          message: 'User info',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: t,
              borderRadius: BorderRadius.circular(6),
              child: child,
            ),
          ),
        ),
      );
    }

    Widget placeholder() {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: border,
        ),
        child: Center(
          child: Text(
            initials,
            style: MatrixTheme.messageTimeStyle.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: fg,
              height: 1,
            ),
          ),
        ),
      );
    }

    final uri = widget.mxcUri.trim();
    if (uri.isEmpty || _loadFuture == null) {
      return wrapInteractive(
        SizedBox(
          width: _kMessageAvatarSize,
          height: _kMessageAvatarSize,
          child: placeholder(),
        ),
      );
    }

    return wrapInteractive(
      SizedBox(
        width: _kMessageAvatarSize,
        height: _kMessageAvatarSize,
        child: FutureBuilder<Uint8List?>(
        future: _loadFuture,
        builder: (context, snap) {
          if (snap.hasError) {
            return placeholder();
          }
          final data = snap.data;
          if (data != null && data.isNotEmpty) {
            final thumbDecode = timelineThumbImageDecodeCacheParams(
              logicalWidth: _kMessageAvatarSize,
              logicalHeight: _kMessageAvatarSize,
              context: context,
            );
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: DecoratedBox(
                decoration: BoxDecoration(border: border),
                child: Image.memory(
                  data,
                  fit: BoxFit.cover,
                  width: _kMessageAvatarSize,
                  height: _kMessageAvatarSize,
                  cacheWidth: thumbDecode.cacheWidth,
                  cacheHeight: thumbDecode.cacheHeight,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => placeholder(),
                ),
              ),
            );
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(6),
                border: border,
              ),
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: fg.withValues(alpha: 0.85),
                  ),
                ),
              ),
            );
          }
          return placeholder();
        },
        ),
      ),
    );
  }
}

String _readReceiptDetailTooltip(BuildContext context, Message message) {
  final n = message.readReceiptCount;
  final ms = message.readReceiptLatestTimestampMs;
  var suffix = '';
  if (ms > BigInt.zero) {
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
      final loc = MaterialLocalizations.of(context);
      final date = loc.formatFullDate(dt);
      final tod = loc.formatTimeOfDay(
        TimeOfDay.fromDateTime(dt),
        alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
      );
      suffix = '\n$date · $tod';
    } catch (_) {
      suffix = '';
    }
  }
  if (n > 1) return 'Read by $n members$suffix';
  if (n == 1) return 'Read$suffix';
  if (message.sendState == EventSendStateKind.delivered) {
    return 'Delivered$suffix';
  }
  return 'Sent$suffix';
}

/// Outgoing bubbles only: local echo / server ack + aggregated `m.read` from [Message.readReceiptCount].
bool _showOutgoingReceiptStrip(Message message, {required bool hiddenLocal}) {
  if (!message.isOwn) return false;
  if (message.messageType != MessageType.message) return false;
  if (message.isRedacted || hiddenLocal) return false;
  if (message.sendState == EventSendStateKind.failed) return false;
  return true;
}

class _OutgoingReceiptStrip extends StatelessWidget {
  const _OutgoingReceiptStrip({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = message.sendState == EventSendStateKind.pending;
    if (pending) {
      return Icon(
        Icons.schedule_rounded,
        size: 15,
        color: theme.colorScheme.tertiary.withValues(alpha: 0.9),
      );
    }

    final readCount = message.readReceiptCount;
    final readColor = theme.colorScheme.primary;
    final sentColor = theme.colorScheme.onSurface.withValues(alpha: 0.45);
    final Widget icon = readCount > 0
        ? Icon(
            Icons.done_all_rounded,
            size: 16,
            color: readColor,
          )
        : Icon(
            Icons.done_all_rounded,
            size: 16,
            color: sentColor,
          );

    final tooltipMessage = _readReceiptDetailTooltip(context, message);

    if (readCount > 1) {
      return Tooltip(
        message: tooltipMessage,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 3),
            Text(
              '$readCount',
              style: MatrixTheme.messageTimeStyle.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: readColor.withValues(alpha: 0.95),
              ),
            ),
          ],
        ),
      );
    }

    if (readCount == 1) {
      return Tooltip(
        message: tooltipMessage,
        child: icon,
      );
    }

    return Tooltip(
      message: tooltipMessage,
      child: icon,
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
    RoomMessageKind.call => false,
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

    // Same visual layout for incoming and outgoing (no RTL-style mirroring).
    final inner = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: borderColor, width: 3),
        ),
        color: theme.colorScheme.surface.withValues(alpha: 0.22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Text(
              '> RE: $senderLabel',
              textAlign: TextAlign.start,
              style: theme.textTheme.labelMedium?.copyWith(
                color: headerColor,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
              ),
            ),
          ),
          if (parentDeleted) ...[
            const SizedBox(height: 6),
            _timelineDeletedReplyTargetRow(context),
          ],
          if (!parentDeleted && !showMedia && message.inReplyToPreview.isNotEmpty) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: Text(
                message.inReplyToPreview,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                  height: 1.3,
                ),
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

  Future<Uint8List?> _loadAndDownscaleThumb() async {
    final raw = await widget.loadMessageMedia(widget.eventId, thumbnail: true);
    if (raw == null || raw.isEmpty) return null;
    if (!_isTimelineRasterBytes(raw)) return null;
    final e = timelineThumbDecodeExtentPx(_kInlineReplyThumb);
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
    if (widget.kind == RoomMessageKind.audio) {
      _future = Future<Uint8List?>.value(null);
    } else {
      _future = _loadAndDownscaleThumb();
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
          final thumbDecode = timelineThumbImageDecodeCacheParams(
            logicalWidth: _kInlineReplyThumb,
            logicalHeight: _kInlineReplyThumb,
            context: context,
          );
          return framed(
            Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: thumbDecode.cacheWidth,
              cacheHeight: thumbDecode.cacheHeight,
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
    RoomMessageKind.call => Icons.call_outlined,
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
    this.placementLeftRight = true,
    this.onVote,
  });

  static const Color _incomingPollText = Color(0xFF58A6FF);

  final Message message;
  final Color accent;
  final bool isOutgoing;
  /// When false, poll chrome aligns like a thread (all from the start).
  final bool placementLeftRight;
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

    final layoutOutgoing =
        widget.placementLeftRight && widget.isOutgoing;

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
          crossAxisAlignment: layoutOutgoing
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: layoutOutgoing
                  ? [
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
                      const Spacer(),
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
                      const SizedBox(width: 8),
                      Icon(
                        Icons.how_to_vote_outlined,
                        size: 18,
                        color: widget.accent.withValues(alpha: 0.95),
                      ),
                    ]
                  : [
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
            SizedBox(
              width: double.infinity,
              child: Text(
                _kindSubtitle(kind),
                textAlign:
                    layoutOutgoing ? TextAlign.end : TextAlign.start,
                style: TextStyle(
                  color: MatrixTheme.matrixDarkGreen.withValues(alpha: 0.92),
                  height: 1.35,
                  fontSize: 11,
                  fontFamily: MatrixTheme.fontFamily,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Divider(
              height: 1,
              thickness: 1,
              color: panelBorder.withValues(alpha: 0.65),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: Text(
                widget.message.content,
                textAlign:
                    layoutOutgoing ? TextAlign.end : TextAlign.start,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: qColor,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  fontFamily: MatrixTheme.fontFamily,
                ),
              ),
            ),
            if (parsed != null) ...[
              const SizedBox(height: 10),
              Row(
                children: layoutOutgoing
                    ? [
                        Expanded(
                          child: Text(
                            'Up to $maxSel choice${maxSel == 1 ? '' : 's'} · '
                            '$totalSel response${totalSel == 1 ? '' : 's'}',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                              fontFamily: MatrixTheme.fontFamily,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.tune,
                          size: 14,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                        ),
                      ]
                    : [
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
                  children: layoutOutgoing
                      ? [
                          Expanded(
                            child: Text(
                              'Sending poll…',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                                fontFamily: MatrixTheme.fontFamily,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: widget.accent.withValues(alpha: 0.8),
                            ),
                          ),
                        ]
                      : [
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
                    children: layoutOutgoing
                        ? [
                            Expanded(
                              child: Text(
                                'Tap an option to vote',
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  color: widget.accent.withValues(alpha: 0.88),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: MatrixTheme.fontFamily,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.touch_app_outlined,
                              size: 15,
                              color: widget.accent.withValues(alpha: 0.8),
                            ),
                          ]
                        : [
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
    /// Classic chat (opposite sides) vs thread-style (all from the start).
    required this.messagePlacementLeftRight,
    required this.loadMessageMedia,
    required this.loadSenderAvatar,
    this.ownProfileInitials,
    this.ownAvatarMxcFallback,
    this.senderAvatarMxcByUserId,
    this.onRetryFailedSend,
    this.onOpenAttachment,
    this.jumpToEventNotifier,
    required this.isGroupRoom,
    required this.onToggleReaction,
    required this.onShowReactionReactors,
    this.onPollVote,
    this.onOpenMessageActions,
    this.onSenderAvatarTap,
    this.searchHighlightQuery,
  });

  /// Incoming bubbles: blue accent so they read clearly against terminal-green “sent” styling.
  static const Color _receivedAccent = Color(0xFF58A6FF);

  final Message message;

  /// In-conversation search: highlight matching substrings in body and sender line.
  final String? searchHighlightQuery;

  final String roomId;
  final bool isOutgoing;
  final bool messagePlacementLeftRight;
  final Future<Uint8List?> Function(String eventId, {bool thumbnail})
  loadMessageMedia;
  final Future<Uint8List?> Function(String mxcUri) loadSenderAvatar;
  /// Logged-in user's initials from profile account data (timeline avatar fallback).
  final String? ownProfileInitials;
  /// Account avatar MXC when timeline has not filled [Message.senderAvatarMxc] yet.
  final String? ownAvatarMxcFallback;

  /// Live avatars from room membership; overrides per-event [Message.senderAvatarMxc] when present.
  final Map<String, String>? senderAvatarMxcByUserId;

  final Future<void> Function(String transactionId)? onRetryFailedSend;
  final Future<void> Function(Message message)? onOpenAttachment;
  final ValueNotifier<String?>? jumpToEventNotifier;
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

  /// ⋮ opens reply / react / delete (sheet on mobile, [showMenu] on desktop).
  final void Function(BuildContext context, Offset anchorGlobal)?
  onOpenMessageActions;

  final void Function(BuildContext context, Message message)? onSenderAvatarTap;

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
    final stripAsOutgoing = messagePlacementLeftRight && isOutgoing;
    final tagColor = accentColor.withValues(alpha: 0.5);
    final countStyle = MatrixTheme.messageTimeStyle.copyWith(
      fontSize: 9,
      height: 1,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );

    final rxLabel = Padding(
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
    );

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!stripAsOutgoing) ...[rxLabel, const SizedBox(width: 6)],
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment:
                  stripAsOutgoing ? WrapAlignment.end : WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: message.reactions.map((e) {
                final own = e.containsOwn;
                final hitPad = isGroupRoom
                    ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                    : const EdgeInsets.symmetric(horizontal: 4, vertical: 2);
                return InkWell(
                  onTap: () => _onReactionChipTap(e),
                  onLongPress: isGroupRoom
                      ? () => _onReactionChipLongPress(context, e)
                      : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: hitPad,
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
                  ),
                );
              }).toList(),
            ),
          ),
          if (stripAsOutgoing) ...[const SizedBox(width: 6), rxLabel],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lr = messagePlacementLeftRight;
    final layoutOutgoing = lr && isOutgoing;
    final theme = Theme.of(context);
    final sendAccentColor = switch (message.sendState) {
      EventSendStateKind.failed => theme.colorScheme.error,
      EventSendStateKind.pending => theme.colorScheme.tertiary,
      EventSendStateKind.delivered => theme.colorScheme.primary,
    };
    final barColor = isOutgoing ? sendAccentColor : _receivedAccent;
    final pending = message.sendState == EventSendStateKind.pending;
    final hiddenLocal = TimelineLocalHiddenStore.isHidden(message);
    final showMenu =
        onOpenMessageActions != null &&
        message.messageType == MessageType.message &&
        !message.isRedacted &&
        !hiddenLocal;
    final isTimelineMsg = message.messageType == MessageType.message;
    final showAvatarFace =
        isTimelineMsg && !message.isRedacted && !hiddenLocal;
    final showInlineHeader = showAvatarFace;
    final showClassicMetaFooter = !showInlineHeader;
    final showReceiptInClassicFooter = showClassicMetaFooter &&
        _showOutgoingReceiptStrip(message, hiddenLocal: hiddenLocal);
    final showOutgoingReceiptInline = showInlineHeader &&
        isOutgoing &&
        _showOutgoingReceiptStrip(message, hiddenLocal: hiddenLocal);
    final bubbleMaxWidth = MediaQuery.sizeOf(context).width * 0.88;
    final incomingBg = Color.alphaBlend(
      _receivedAccent.withValues(alpha: 0.11),
      theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.88),
    );
    final outgoingBg = Color.alphaBlend(
      theme.colorScheme.primary.withValues(alpha: 0.14),
      theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
    );
    final metaNameStyle = MatrixTheme.messageTimeStyle.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      height: 1.25,
      color: isOutgoing
          ? theme.colorScheme.primary
          : _receivedAccent.withValues(alpha: 0.94),
    );
    final metaTimeStyle = MatrixTheme.messageTimeStyle.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      height: 1.25,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    final metaSepStyle = MatrixTheme.messageTimeStyle.copyWith(
      fontSize: 11,
      height: 1.25,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
    );
    final messageBodyStyle = theme.textTheme.bodyLarge?.copyWith(
      height: 1.38,
      fontWeight: FontWeight.w500,
      fontFamily: MatrixTheme.fontFamily,
      color: isOutgoing ? theme.colorScheme.primary : _receivedAccent,
    );
    final linkStyle = messageBodyStyle?.copyWith(
      decoration: TextDecoration.underline,
      decorationColor:
          isOutgoing ? theme.colorScheme.primary : _receivedAccent,
    );
    final searchHighlightStyle = _timelineSearchHighlightStyle(theme.colorScheme);
    final showOverlayActions = pending || showMenu;
    final bubbleCrossAxis =
        layoutOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleTextAlign = layoutOutgoing ? TextAlign.end : TextAlign.start;
    final metaTextAlign = layoutOutgoing ? TextAlign.end : TextAlign.start;

    final avatarMxc = _effectiveTimelineAvatarMxc(
      message,
      ownAvatarMxcFallback,
      senderAvatarMxcByUserId: senderAvatarMxcByUserId,
    );

    final VoidCallback? onAvatarTap =
        onSenderAvatarTap != null && message.senderUserId.trim().isNotEmpty
        ? () => onSenderAvatarTap!(context, message)
        : null;

    final bubbleCard = Container(
        margin: EdgeInsetsDirectional.only(
          bottom: 10,
          start: lr ? (isOutgoing ? 36 : 6) : 6,
          end: lr ? (isOutgoing ? 6 : 36) : 44,
        ),
        constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,

              /// Long-press opens the quick reaction picker.
              onLongPress: _canReactToMessage
                  ? () {
                      HapticFeedback.lightImpact();
                      _openQuickReactionPicker(context);
                    }
                  : null,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsetsDirectional.only(
                      start: lr
                          ? (isOutgoing
                              ? (showOverlayActions ? 40 : 12)
                              : 12)
                          : 12,
                      top: 10,
                      end: lr
                          ? (isOutgoing
                              ? 12
                              : (showOverlayActions ? 40 : 12))
                          : (showOverlayActions ? 40 : 12),
                      bottom: 10,
                    ),
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                        start: lr
                            ? (isOutgoing
                                ? BorderSide.none
                                : BorderSide(color: barColor, width: 3))
                            : BorderSide(color: barColor, width: 3),
                        end: lr
                            ? (isOutgoing
                                ? BorderSide(color: barColor, width: 3)
                                : BorderSide.none)
                            : BorderSide.none,
                      ),
                      color: isOutgoing ? outgoingBg : incomingBg,
                    ),
                    child: Column(
                      crossAxisAlignment: bubbleCrossAxis,
                      children: [
                      if (showInlineHeader)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (!layoutOutgoing) ...[
                                _MessageSenderAvatar(
                                  mxcUri: avatarMxc,
                                  initials: _timelineMessageInitials(
                                    message,
                                    ownInitialsOverride: ownProfileInitials,
                                  ),
                                  isOutgoing: isOutgoing,
                                  loadBytes: loadSenderAvatar,
                                  onTap: onAvatarTap,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text.rich(
                                        TextSpan(
                                          children:
                                              _plainTextSearchHighlightSpans(
                                            message.displayName,
                                            searchHighlightQuery,
                                            metaNameStyle,
                                            searchHighlightStyle,
                                          ),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.start,
                                      ),
                                      Text(
                                        message.formattedDate,
                                        style: metaTimeStyle,
                                        textAlign: TextAlign.start,
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Text.rich(
                                        TextSpan(
                                          children:
                                              _plainTextSearchHighlightSpans(
                                            message.displayName,
                                            searchHighlightQuery,
                                            metaNameStyle,
                                            searchHighlightStyle,
                                          ),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.end,
                                      ),
                                      Align(
                                        alignment:
                                            AlignmentDirectional.centerEnd,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              message.formattedDate,
                                              style: metaTimeStyle,
                                              textAlign: TextAlign.end,
                                            ),
                                            if (showOutgoingReceiptInline) ...[
                                              const SizedBox(width: 5),
                                              _OutgoingReceiptStrip(
                                                message: message,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _MessageSenderAvatar(
                                  mxcUri: avatarMxc,
                                  initials: _timelineMessageInitials(
                                    message,
                                    ownInitialsOverride: ownProfileInitials,
                                  ),
                                  isOutgoing: isOutgoing,
                                  loadBytes: loadSenderAvatar,
                                  onTap: onAvatarTap,
                                ),
                              ],
                            ],
                          ),
                        ),
                      if (message.isRedacted)
                        _timelineDeletedBubbleBody(
                          context,
                          barColor,
                          isOutgoing,
                          placementLeftRight: lr,
                        )
                      else if (hiddenLocal)
                        _timelineRemovedOnDeviceBubbleBody(
                          context,
                          barColor,
                          isOutgoing,
                          placementLeftRight: lr,
                        )
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
                            placementLeftRight: lr,
                            onVote:
                                onPollVote != null && message.eventId.isNotEmpty
                                ? (ids) => onPollVote!(message.eventId, ids)
                                : null,
                          )
                        else if (message.roomMsgKind == RoomMessageKind.call)
                          _CallTimelineBubbleBody(
                            label: message.content.trim().isNotEmpty
                                ? message.content.trim()
                                : 'Call',
                            accent: barColor,
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
                              audioDurationMs: message.audioDurationMs,
                              audioWaveform: message.audioWaveform,
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
                          SizedBox(
                            width: double.infinity,
                            child: SelectableText.rich(
                              TextSpan(
                                children: _linkifySpansWithSearchHighlight(
                                  message.content,
                                  searchHighlightQuery,
                                  messageBodyStyle,
                                  linkStyle,
                                  searchHighlightStyle,
                                  (link) => openMatrixUrl(context, link.url),
                                ),
                              ),
                              textAlign: bubbleTextAlign,
                            ),
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
                        Align(
                          alignment: layoutOutgoing
                              ? AlignmentDirectional.centerEnd
                              : AlignmentDirectional.centerStart,
                          child: Text(
                            message.sendError,
                            textAlign: bubbleTextAlign,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                      if (message.sendState == EventSendStateKind.failed &&
                          message.sendRecoverable &&
                          message.transactionId.isNotEmpty &&
                          onRetryFailedSend != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: layoutOutgoing
                              ? AlignmentDirectional.centerEnd
                              : AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: () =>
                                onRetryFailedSend!(message.transactionId),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Retry send'),
                          ),
                        ),
                      ],
                      if (showClassicMetaFooter)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      ..._plainTextSearchHighlightSpans(
                                        message.displayName,
                                        searchHighlightQuery,
                                        metaNameStyle,
                                        searchHighlightStyle,
                                      ),
                                      TextSpan(text: ' · ', style: metaSepStyle),
                                      TextSpan(
                                        text: message.formattedDate,
                                        style: metaTimeStyle,
                                      ),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: metaTextAlign,
                                ),
                              ),
                              if (showReceiptInClassicFooter)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 6,
                                  ),
                                  child: _OutgoingReceiptStrip(
                                    message: message,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (showOverlayActions)
                  PositionedDirectional(
                    top: 0,
                    start: lr && isOutgoing ? 0 : null,
                    end: lr && isOutgoing ? null : 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: lr && isOutgoing
                          ? [
                              if (showMenu)
                                Builder(
                                  builder: (buttonContext) {
                                    return IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      iconSize: 20,
                                      tooltip: 'Message actions',
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        final box = buttonContext
                                            .findRenderObject() as RenderBox?;
                                        final o = box?.localToGlobal(
                                              Offset.zero,
                                            ) ??
                                            Offset.zero;
                                        onOpenMessageActions!(
                                          buttonContext,
                                          o,
                                        );
                                      },
                                      icon: Icon(
                                        Icons.more_horiz,
                                        color: theme.colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.85),
                                      ),
                                    );
                                  },
                                ),
                              if (pending)
                                Padding(
                                  padding:
                                      const EdgeInsetsDirectional.only(
                                    top: 6,
                                    start: 2,
                                  ),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.tertiary,
                                    ),
                                  ),
                                ),
                            ]
                          : [
                              if (pending)
                                Padding(
                                  padding:
                                      const EdgeInsetsDirectional.only(
                                    top: 6,
                                    end: 2,
                                  ),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.tertiary,
                                    ),
                                  ),
                                ),
                              if (showMenu)
                                Builder(
                                  builder: (buttonContext) {
                                    return IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      iconSize: 20,
                                      tooltip: 'Message actions',
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        final box = buttonContext
                                            .findRenderObject() as RenderBox?;
                                        final o = box?.localToGlobal(
                                              Offset.zero,
                                            ) ??
                                            Offset.zero;
                                        onOpenMessageActions!(
                                          buttonContext,
                                          o,
                                        );
                                      },
                                      icon: Icon(
                                        Icons.more_horiz,
                                        color: theme.colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.85),
                                      ),
                                    );
                                  },
                                ),
                            ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        ),
      );

    return Align(
      alignment: layoutOutgoing
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: bubbleCard,
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

/// Wider slot so MSC / placeholder waveform bars are visible in the bubble.
const double _kAudioWaveformThumbW = 76;

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
    case RoomMessageKind.call:
    case RoomMessageKind.other:
      return false;
  }
}

/// Rows that count as “chat” for the jump-down unread badge (mirrors bubble visibility).
bool _countsTowardUnreadFab(Message m) {
  if (m.messageType != MessageType.message) return false;
  if (TimelineLocalHiddenStore.isHidden(m)) return false;
  if (m.content.isEmpty &&
      !_wantsMediaPreview(m) &&
      !m.isRedacted) {
    return false;
  }
  return true;
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
    RoomMessageKind.call => 'call',
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
  BigInt? audioDurationMs,
}) {
  final ext = _timelineExtLower(fileLabel);
  final mime = _timelineAttachmentMimeLabel(mediaMimetype, kind, ext);
  final sizeStr = _formatTimelineMediaSize(mediaSizeBytes);
  final metaBits = <String>[mime];
  if (sizeStr != null) metaBits.add(sizeStr);
  final audioDur = audioDurationMs ?? BigInt.zero;
  if (kind == RoomMessageKind.audio && audioDur > BigInt.zero) {
    final msTotal = audioDur.toInt().clamp(0, 1 << 30);
    final d = Duration(milliseconds: msTotal);
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    metaBits.add('$mm:$ss');
  }
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
  BigInt? audioDurationMs,
}) {
  final icon = switch (kind) {
    RoomMessageKind.image => Icons.image_not_supported_outlined,
    RoomMessageKind.video => Icons.videocam_off_outlined,
    RoomMessageKind.file => _timelineFileIcon(ext),
    RoomMessageKind.poll => Icons.poll_outlined,
    _ => Icons.perm_media_outlined,
  };
  final thumbSize = mediaPreviewWidth > 0 && mediaPreviewHeight > 0
      ? timelineThumbBoxFromEventDimensions(
          mediaPreviewWidth,
          mediaPreviewHeight,
        )
      : const Size(kTimelineThumbPortraitW, kTimelineThumbPortraitH);
  final placeholder = SizedBox(
    width: thumbSize.width,
    height: thumbSize.height,
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
      audioDurationMs: audioDurationMs,
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
    required this.audioDurationMs,
    required this.audioWaveform,
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
  final BigInt audioDurationMs;
  final List<double> audioWaveform;
  final Future<Uint8List?> Function(String eventId, {bool thumbnail})
  loadMessageMedia;
  final Future<void> Function()? onOpen;

  @override
  State<_MessageMediaPreview> createState() => _MessageMediaPreviewState();
}

class _MessageMediaPreviewState extends State<_MessageMediaPreview> {
  Uint8List? _bytes;
  RasterPreviewMeta? _previewMeta;
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
      var displayB = await widget.loadMessageMedia(
        widget.timelineMediaKey,
        thumbnail: true,
      );
      if (displayB != null &&
          displayB.isNotEmpty &&
          !_isTimelineRasterBytes(displayB)) {
        displayB = null;
      }
      RasterPreviewMeta? meta;
      if (displayB != null && displayB.isNotEmpty) {
        meta = await decodeRasterPreviewMeta(displayB);
        if (meta == null) {
          displayB = null;
        } else {
          final oriented = orientedIntrinsicForLayout(
            meta.rawSize,
            meta.exifOrientation,
          );
          final thumbBox = timelineThumbBoxPreservingAspect(oriented);
          final longLogical = thumbBox.width >= thumbBox.height
              ? thumbBox.width
              : thumbBox.height;
          final longPx = timelineThumbDecodeExtentPx(longLogical);
          final preEncodeMeta = meta;
          final small = await encodeRasterPngMaxLongEdgeWithMeta(
            displayB,
            longPx,
            preEncodeMeta,
          );
          if (small != null && small.isNotEmpty) {
            displayB = small;
            // Re-encode path bakes orientation into pixels; do not rotate again.
            final dm = await decodeRasterPreviewMeta(small);
            meta = dm != null
                ? RasterPreviewMeta(dm.rawSize, 1)
                : RasterPreviewMeta(oriented, 1);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _bytes = displayB;
        _previewMeta = meta;
        _loading = false;
        if (displayB != null && displayB.isNotEmpty) {
          _error = null;
        } else if (!_canUseBlurhashAsThumbnailFallback()) {
          _error = 'Preview unavailable';
        } else {
          _error = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_canUseBlurhashAsThumbnailFallback()) {
          _error = null;
        } else {
          _error = '$e';
        }
      });
    }
  }

  /// Image / video / file events may carry MSC2448 blurhash; use it when bytes are not ready.
  bool _canUseBlurhashAsThumbnailFallback() {
    if (widget.mediaBlurhash.trim().isEmpty) return false;
    return widget.kind == RoomMessageKind.image ||
        widget.kind == RoomMessageKind.video ||
        widget.kind == RoomMessageKind.file;
  }

  /// Thumb slot while loading, or when thumbnail download failed but [mediaBlurhash] is set.
  Widget _mediaPreviewThumbBlurhashOrSpinner(ThemeData theme) {
    final frame = timelineThumbBoxFromEventDimensions(
      widget.mediaPreviewWidth,
      widget.mediaPreviewHeight,
    );
    final tw = frame.width;
    final th = frame.height;
    final scheme = theme.colorScheme;
    final blur = widget.mediaBlurhash.trim();
    return SizedBox(
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
  }

  Widget _mediaPreviewPanelWithBlurhashThumb(ThemeData theme) {
    final thumb = _mediaPreviewThumbBlurhashOrSpinner(theme);
    final showHint = widget.onOpen != null;
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
        showTapHint: showHint,
        audioDurationMs: widget.audioDurationMs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      final extra = _extraCaption(theme);
      final panel = _mediaPreviewPanelWithBlurhashThumb(theme);
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
        audioDurationMs: widget.audioDurationMs,
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
      final wf = widget.audioWaveform;
      final hasRealWaveform =
          wf.isNotEmpty && wf.any((v) => v > 0.004);
      final samples = hasRealWaveform
          ? wf
          : placeholderAudioWaveformBars(
              widget.timelineMediaKey.isEmpty
                  ? widget.fileLabel
                  : widget.timelineMediaKey,
              barCount: 28,
            );
      final audioThumb = AudioMessageWaveformBars(
        samples: samples,
        height: kTimelineThumbPortraitH.toDouble(),
        width: _kAudioWaveformThumbW,
        isPlaceholder: !hasRealWaveform,
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
          audioDurationMs: widget.audioDurationMs,
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
    if (_bytes == null || _bytes!.isEmpty) {
      if (_canUseBlurhashAsThumbnailFallback()) {
        final extra = _extraCaption(theme);
        final panel = _mediaPreviewPanelWithBlurhashThumb(theme);
        return _maybeWrapOpen(
          extra != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [panel, extra],
                )
              : panel,
        );
      }
      return const SizedBox.shrink();
    }
    final meta = _previewMeta;
    final preview = meta == null
        ? (_canUseBlurhashAsThumbnailFallback()
              ? _mediaPreviewPanelWithBlurhashThumb(theme)
              : _timelineNoThumbnailRow(
                  theme: theme,
                  kind: widget.kind,
                  ext: _timelineExtLower(widget.fileLabel),
                  fileLabel: widget.fileLabel,
                  mediaMimetype: widget.mediaMimetype,
                  mediaSizeBytes: widget.mediaSizeBytes,
                  mediaPreviewWidth: widget.mediaPreviewWidth,
                  mediaPreviewHeight: widget.mediaPreviewHeight,
                  showTapHint: widget.onOpen != null,
                  audioDurationMs: widget.audioDurationMs,
                ))
        : _buildThumbnailWithSideInfo(context, theme, meta);
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
    BuildContext context,
    ThemeData theme,
    RasterPreviewMeta meta,
  ) {
    final oriented = orientedIntrinsicForLayout(
      meta.rawSize,
      meta.exifOrientation,
    );
    final portrait = oriented.height > oriented.width;
    final box = timelineThumbBoxPreservingAspect(oriented);
    final tw = box.width;
    final th = box.height;
    final thumbDecode = timelineThumbImageDecodeCacheParams(
      logicalWidth: tw,
      logicalHeight: th,
      context: context,
    );
    Widget thumbDecodeError(_, Object __, StackTrace? ___) {
      if (_canUseBlurhashAsThumbnailFallback()) {
        return BlurHash(
          hash: widget.mediaBlurhash.trim(),
          imageFit: BoxFit.cover,
        );
      }
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

    final turns = exifQuarterTurns(meta.exifOrientation);
    final imageCore = turns == 0
        ? Image.memory(
            _bytes!,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            cacheWidth: thumbDecode.cacheWidth,
            cacheHeight: thumbDecode.cacheHeight,
            errorBuilder: thumbDecodeError,
          )
        : RotatedBox(
            quarterTurns: turns,
            child: Image.memory(
              _bytes!,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              cacheWidth: thumbDecode.cacheWidth,
              cacheHeight: thumbDecode.cacheHeight,
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
        audioDurationMs: widget.audioDurationMs,
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
