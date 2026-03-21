import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:matrix/src/features/conversation/domain/models/conversation_state.dart'
    hide MessageType;
import 'package:matrix_sdk/matrix_sdk.dart'
    show EventSendStateKind, Message, MessageType, RoomMessageKind;

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

  @override
  State<PaginatedMessageList> createState() => PaginatedMessageListState();
}

class PaginatedMessageListState extends State<PaginatedMessageList> {
  final _controller = ScrollController();
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
    _controller.removeListener(_onScroll);
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
      if (widget.initialMessages.any((m) => _messageMatchesJumpTarget(m, eventId))) {
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
            // While jumping (or showing the post-jump highlight), widen the build
            // cache so lazy slivers materialize rows far from the viewport.
            cacheExtent: (_pendingJumpEventId != null || _jumpHighlightId != null)
                ? 200000.0
                : null,
            slivers: [
              SliverList.builder(
                itemCount: display.length,
                itemBuilder: (context, index) {
                  final message = display[index];

                  // Virtual rows — no bubble. Real [MessageType.message] can have
                  // empty [content] (e.g. image/file with no caption); those must
                  // still build so jump-to-event GlobalKeys attach.
                  if ([
                    MessageType.dateDivider,
                    MessageType.readMarker,
                    MessageType.timelineStart,
                  ].contains(message.messageType)) {
                    return const SizedBox.shrink();
                  }
                  if (message.messageType == MessageType.message &&
                      message.content.isEmpty &&
                      !_wantsMediaPreview(message)) {
                    return const SizedBox.shrink();
                  }

                  final jumpKey = _jumpKey;
                  final pendingId = _pendingJumpEventId;
                  final useJumpKey = jumpKey != null &&
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
                      jumpHighlighted: _jumpHighlightId != null &&
                          _messageMatchesJumpTarget(
                            message,
                            _jumpHighlightId!,
                          ),
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
    bool jumpHighlighted = false,
  }) {
    final bubble = MessageBubble(
      message: m,
      roomId: roomId,
      isOutgoing: m.isOwn,
      loadMessageMedia: loadMessageMedia,
      onRetryFailedSend: widget.onRetryFailedSend,
      onOpenAttachment: onOpenAttachment,
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
                  border: Border.all(
                    color: scheme.tertiary,
                    width: 2.5,
                  ),
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

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.roomId,
    required this.isOutgoing,
    required this.loadMessageMedia,
    this.onRetryFailedSend,
    this.onOpenAttachment,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
              Text(message.formattedDate, style: theme.textTheme.bodySmall),
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
                if (_wantsMediaPreview(message))
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
                      loadMessageMedia: loadMessageMedia,
                      onOpen: onOpenAttachment != null &&
                              (message.eventId.isNotEmpty ||
                                  message.transactionId.isNotEmpty)
                          ? () => onOpenAttachment!(message)
                          : null,
                    ),
                  )
                else
                  Text(
                    message.content,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isOutgoing ? null : _receivedAccent,
                    ),
                  ),
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
                    onPressed: () => onRetryFailedSend!(message.transactionId),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry send'),
                  ),
                ],
              ],
            ),
          ),
        ],
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
    _ => 'attachment',
  };
}

/// Shown when the homeserver has no thumbnail (we no longer download the full file in the timeline).
Widget _timelineNoThumbnailRow({
  required ThemeData theme,
  required RoomMessageKind kind,
  required String ext,
  required String fileLabel,
  required String mediaMimetype,
  required BigInt mediaSizeBytes,
}) {
  final icon = switch (kind) {
    RoomMessageKind.image => Icons.image_not_supported_outlined,
    RoomMessageKind.video => Icons.videocam_off_outlined,
    RoomMessageKind.file => _timelineFileIcon(ext),
    _ => Icons.perm_media_outlined,
  };
  final name = fileLabel.trim().isEmpty
      ? 'Attachment'
      : p.basename(fileLabel.trim());
  final metaLine = [
    _timelineAttachmentMimeLabel(mediaMimetype, kind, ext),
    if (_formatTimelineMediaSize(mediaSizeBytes) != null)
      _formatTimelineMediaSize(mediaSizeBytes)!,
  ].join(' · ');
  const placeholderSize = 26.0;
  final placeholder = SizedBox(
    width: placeholderSize,
    height: placeholderSize,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        color: theme.colorScheme.surface,
      ),
      child: Icon(
        icon,
        size: 13,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
  final textColumn = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
          height: 1.25,
        ),
      ),
      if (metaLine.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          metaLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.25,
          ),
        ),
      ],
    ],
  );
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      placeholder,
      const SizedBox(width: 6),
      Flexible(child: textColumn),
    ],
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
      // Match loaded layout: fixed frame + side info; spinner in the thumb slot.
      const tw = _kTimelineThumbPortraitW;
      const th = _kTimelineThumbPortraitH;
      final scheme = theme.colorScheme;
      final thumb = SizedBox(
        width: tw,
        height: th,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.55),
            ),
            color: scheme.surfaceContainerLow.withValues(alpha: 0.35),
          ),
          child: Center(
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
      final info = _thumbnailSideInfo(theme);
      const gap = SizedBox(width: 5);
      final row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [thumb, gap, Expanded(child: info)],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row,
          if (extra != null) extra,
        ],
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
      final rawLabel = widget.fileLabel.trim();
      final title = rawLabel.isEmpty
          ? 'Audio attachment'
          : p.basename(rawLabel);
      final audioMetaLine = [
        _timelineAttachmentMimeLabel(
          widget.mediaMimetype,
          widget.kind,
          _timelineExtLower(widget.fileLabel),
        ),
        if (_formatTimelineMediaSize(widget.mediaSizeBytes) != null)
          _formatTimelineMediaSize(widget.mediaSizeBytes)!,
      ].join(' · ');
      final audioTextColumn = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
              height: 1.25,
            ),
          ),
          if (audioMetaLine.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              audioMetaLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.25,
              ),
            ),
          ],
        ],
      );
      final tap = widget.onOpen != null
          ? Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'Tap to play',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            )
          : null;
      final row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.audiotrack,
            color: theme.colorScheme.primary,
            size: 18,
          ),
          const SizedBox(width: 6),
          Expanded(child: audioTextColumn),
          if (tap != null) tap,
        ],
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
  Widget _buildThumbnailWithSideInfo(ThemeData theme, _TimelinePreviewMeta meta) {
    final oriented = _orientedIntrinsicForLayout(
      meta.rawSize,
      meta.exifOrientation,
    );
    final portrait = oriented.height > oriented.width;
    final tw = portrait ? _kTimelineThumbPortraitW : _kTimelineThumbLandscapeW;
    final th = portrait ? _kTimelineThumbPortraitH : _kTimelineThumbLandscapeH;
    final err = _timelineNoThumbnailRow(
      theme: theme,
      kind: widget.kind,
      ext: _timelineExtLower(widget.fileLabel),
      fileLabel: widget.fileLabel,
      mediaMimetype: widget.mediaMimetype,
      mediaSizeBytes: widget.mediaSizeBytes,
    );
    final turns = _exifQuarterTurns(meta.exifOrientation);
    final imageCore = turns == 0
        ? Image.memory(
            _bytes!,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => err,
          )
        : RotatedBox(
            quarterTurns: turns,
            child: Image.memory(
              _bytes!,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => err,
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
    final info = _thumbnailSideInfo(theme);
    const gap = SizedBox(width: 5);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [thumb, gap, Expanded(child: info)],
    );
  }

  /// File name, MIME/type, and size beside the fixed thumbnail.
  Widget _thumbnailSideInfo(ThemeData theme) {
    final ext = _timelineExtLower(widget.fileLabel);
    final mime = _timelineAttachmentMimeLabel(
      widget.mediaMimetype,
      widget.kind,
      ext,
    );
    final sizeStr = _formatTimelineMediaSize(widget.mediaSizeBytes);
    final raw = widget.fileLabel.trim();
    final name = raw.isEmpty ? 'Attachment' : p.basename(raw);
    final typeAndSize = <String>[mime];
    if (sizeStr != null) typeAndSize.add(sizeStr);
    final subline = typeAndSize.join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
            height: 1.25,
          ),
        ),
        if (subline.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.25,
            ),
          ),
        ],
      ],
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
