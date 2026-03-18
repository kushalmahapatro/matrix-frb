import 'package:flutter/material.dart';
import 'package:matrix/src/features/conversation/domain/models/conversation_state.dart'
    hide MessageType;
import 'package:matrix_sdk/matrix_sdk.dart';

/// Result of loading older messages: [older] is the newly loaded chunk (or empty
/// when the parent updated state with full list); [hasMore] indicates if more
/// can be loaded.
typedef LoadOlderResult = (List<Message> older, bool hasMore);

class PaginatedMessageList extends StatefulWidget {
  const PaginatedMessageList({
    super.key,
    required this.initialMessages, // List<Message> ordered oldest → newest
    required this.loadOlder, // Future<LoadOlderResult> Function(Message oldest)
    required this.onVisibleRange, // Optional: for read receipts
  });

  final List<Message> initialMessages;
  final Future<LoadOlderResult> Function(Message oldest) loadOlder;
  final void Function(Message firstVisible, Message lastVisible)?
      onVisibleRange;

  @override
  State<PaginatedMessageList> createState() => _PaginatedMessageListState();
}

class _PaginatedMessageListState extends State<PaginatedMessageList> {
  final _controller = ScrollController();
  bool _isLoadingOlder = false;
  bool _hasMore = true;
  int _unseenNewCount = 0;
  double _beforeMaxScrollExtent = 0;

  bool get _isAtBottom {
    // With reverse:true, bottom == pixels <= 20
    return !_controller.hasClients || _controller.position.pixels <= 20;
  }

  @override
  void initState() {
    super.initState();
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
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  static const double _loadOlderThresholdPx = 80;

  void _onScroll() async {
    // Load older when scrolled near top (reverse:true so top = maxScrollExtent)
    final pos = _controller.position;
    if (pos.pixels >= pos.maxScrollExtent - _loadOlderThresholdPx) {
      _maybeLoadOlder();
    }

    widget.onVisibleRange?.call(_firstVisible(), _lastVisible());
  }

  Future<void> _maybeLoadOlder() async {
    if (_isLoadingOlder || !_hasMore || widget.initialMessages.isEmpty) return;
    setState(() => _isLoadingOlder = true);

    _beforeMaxScrollExtent = _controller.position.maxScrollExtent;
    final oldest = widget.initialMessages.first;
    final (older, hasMore) = await widget.loadOlder(oldest);

    if (!mounted) return;

    if (older.isNotEmpty) {
      setState(() {
        widget.initialMessages.insertAll(0, older);
        _isLoadingOlder = false;
        _hasMore = hasMore &&
            widget.initialMessages.first.messageType != MessageType.timelineStart;
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
      final delta = afterMax - _beforeMaxScrollExtent;
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

                  // Filter system markers here or render date dividers lazily
                  if ([
                        MessageType.dateDivider,
                        MessageType.readMarker,
                      ].contains(message.messageType) ||
                      message.content.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return KeyedSubtree(
                    key: ValueKey(
                      message.eventId,
                    ), // critical for stable layout
                    child: _buildMessageBubble(
                      message,
                      index: index,
                      prev:
                          index + 1 < display.length
                              ? display[index + 1]
                              : null,
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
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
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

  Widget _buildMessageBubble(Message m, {int? index, Message? prev}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // if (showDateDivider) _DateDivider(date: m.timestamp),
        MessageBubble(message: m),
      ],
    );
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '> ${message.displayName}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
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
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 3,
                ),
              ),
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            ),
            child: Text(
              message.content,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
