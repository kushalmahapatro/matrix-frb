import 'package:flutter/material.dart';
import 'package:matrix/src/features/conversation/domain/models/conversation_state.dart'
    hide MessageType;
import 'package:matrix/src/rust/matrix/timelines.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

class PaginatedMessageList extends StatefulWidget {
  const PaginatedMessageList({
    super.key,
    required this.initialMessages, // List<Message> ordered oldest → newest
    required this.loadOlder, // Future<List<Message>> Function(Message oldest)
    required this.onVisibleRange, // Optional: for read receipts
  });

  final List<Message> initialMessages;
  final Future<List<Message>> Function(Message oldest) loadOlder;
  final void Function(Message firstVisible, Message lastVisible)?
  onVisibleRange;

  @override
  State<PaginatedMessageList> createState() => _PaginatedMessageListState();
}

class _PaginatedMessageListState extends State<PaginatedMessageList> {
  final _controller = ScrollController();
  final _messages = <Message>[]; // oldest → newest
  bool _isLoadingOlder = false;
  bool _hasMore = true;
  int _unseenNewCount = 0;

  bool get _isAtBottom {
    // With reverse:true, bottom == pixels <= 20
    return !_controller.hasClients || _controller.position.pixels <= 20;
  }

  @override
  void initState() {
    super.initState();
    _messages.addAll(widget.initialMessages);
    if (_messages.isNotEmpty) {
      _hasMore = _messages.first.messageType != MessageType.timelineStart;
      _controller.addListener(_onScroll);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_messages.length < 5 && _hasMore) {
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

  void _onScroll() async {
    // Load older when scrolled to top (because reverse:true)
    if (_controller.position.atEdge &&
        _controller.position.pixels >=
            _controller.position.maxScrollExtent - 24) {
      // At top
      _maybeLoadOlder();
    }

    // (Optional) visible range reporting
    widget.onVisibleRange?.call(_firstVisible(), _lastVisible());
  }

  Future<void> _maybeLoadOlder() async {
    if (_isLoadingOlder || !_hasMore || _messages.isEmpty) return;
    setState(() => _isLoadingOlder = true);

    // Preserve visual position during insert:
    final beforeMax = _controller.position.maxScrollExtent;

    final oldest = _messages.first;
    final older = await widget.loadOlder(
      oldest,
    ); // returns older messages, oldest → newest
    if (older.isEmpty && mounted) {
      setState(() {
        _isLoadingOlder = false;
        // _hasMore = false;
      });
      return;
    }

    setState(() {
      _messages.insertAll(0, older);
      _isLoadingOlder = false;
      _hasMore = _messages.first.messageType != MessageType.timelineStart;
    });

    // Adjust by delta in maxScrollExtent so content doesn't jump.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      final afterMax = _controller.position.maxScrollExtent;
      final delta = afterMax - beforeMax;
      // With reverse:true, jump forward by delta to keep same items under finger.
      _controller.jumpTo(_controller.position.pixels + delta);
    });
  }

  // Call this when a brand-new message arrives (push from server)
  void addIncoming(Message m) {
    final shouldAutoscroll = _isAtBottom;
    setState(() => _messages.add(m));
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
    return _messages.first;
  }

  Message _lastVisible() {
    return _messages.last;
  }

  @override
  Widget build(BuildContext context) {
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'NO MESSAGES YET\nSTART THE CONVERSATION',
          style: MatrixTheme.captionStyle,
          textAlign: TextAlign.center,
        ),
      );
    }

    final display = _messages.reversed.toList(
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
              // Top loader (shows when asking older, i.e., at top with reverse:true)
              SliverToBoxAdapter(
                child:
                    _isLoadingOlder
                        ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        )
                        : const SizedBox.shrink(),
              ),
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
              // Bottom safe area
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
                    color: Theme.of(context).colorScheme.secondaryContainer,
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
    final showDateDivider =
        prev == null || !_isSameDay(m.dateTime, prev.dateTime);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // if (showDateDivider) _DateDivider(date: m.timestamp),
        MessageBubble(message: m),
      ],
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Message header
          Row(
            children: [
              Text(
                '> ${message.displayName}',
                style: MatrixTheme.messageAuthorStyle,
              ),
              const Spacer(),
              Text(message.formattedDate, style: MatrixTheme.messageTimeStyle),
            ],
          ),

          const SizedBox(height: 4),

          // Message content
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: MatrixTheme.messageDecoration,
            child: Text(message.content, style: MatrixTheme.messageStyle),
          ),
        ],
      ),
    );
  }
}
