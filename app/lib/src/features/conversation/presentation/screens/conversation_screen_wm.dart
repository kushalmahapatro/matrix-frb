import 'dart:async';
import 'dart:io';

import 'package:elementary/elementary.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/timeline_local_hidden_store.dart';
import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';

import 'package:matrix/src/core/state_management/base_state_widget_model.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart'
    show Chat, ChatRoomStatus;
import 'package:matrix/src/features/conversation/domain/models/conversation_state.dart'
    hide MessageType;
import 'package:matrix/src/features/conversation/domain/services/conversation_service.dart';
import 'package:matrix/src/core/video_send_media_prep.dart';
import 'package:matrix/src/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:matrix/src/features/conversation/presentation/screens/media_outgoing_send_screen.dart';
import 'package:matrix/src/features/conversation/presentation/screens/room_info_screen.dart';
import 'package:matrix/src/features/conversation/presentation/widgets/attachment_viewer.dart';
import 'package:matrix/src/features/conversation/presentation/widgets/pagianted_message_list.dart'
    show openTimelineQuickReactionPicker;
import 'package:matrix_sdk/matrix_sdk.dart'
    show
        FileSendPhase,
        FileSendProgress,
        Message,
        MessageReactionEntry,
        MessageType,
        RoomDetails,
        RoomMessageKind;
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:result_dart/result_dart.dart';

class ConversationScreenModel extends ElementaryModel {
  ConversationScreenModel(this.conversationService) : super();
  final ConversationService conversationService;

  Future<Result<List<Message>>> loadMessages(String roomId) async {
    final messages = await conversationService.loadMessages(roomId);
    return messages;
  }

  Future<ConversationInfo> loadRoomInfo(String roomId) async {
    return conversationService.loadRoomInfo(roomId);
  }

  Future<void> toggleTimelineReaction({
    required String roomId,
    required Message message,
    required String reactionKey,
  }) {
    return conversationService.toggleTimelineReaction(
      roomId: roomId,
      message: message,
      reactionKey: reactionKey,
    );
  }

  Future<Result<Unit>> redactTimelineEvent({
    required String roomId,
    required String eventId,
    required String transactionId,
    String? reason,
  }) {
    return conversationService.redactTimelineEvent(
      roomId: roomId,
      eventId: eventId,
      transactionId: transactionId,
      reason: reason,
    );
  }

  Future<Result<String>> sendMessage(
    String roomId,
    String content, {
    String? replyToEventId,
  }) async {
    return conversationService.sendMessage(
      roomId,
      content,
      replyToEventId: replyToEventId,
    );
  }

  Future<Result<String>> sendTimelineFile({
    required String roomId,
    required String filePath,
    String? caption,
    String? mimeType,
  }) {
    return conversationService.sendTimelineFile(
      roomId: roomId,
      filePath: filePath,
      caption: caption,
      mimeType: mimeType,
    );
  }

  Future<Result<Unit>> sendTimelineFileWithProgress({
    required String roomId,
    required String filePath,
    String? caption,
    String? mimeType,
    required void Function(FileSendProgress p) onProgress,
  }) {
    return conversationService.sendTimelineFileWithProgress(
      roomId: roomId,
      filePath: filePath,
      caption: caption,
      mimeType: mimeType,
      onProgress: onProgress,
    );
  }

  Future<Result<Unit>> sendTimelineAttachment({
    required String roomId,
    required String originalFilePath,
    AppTimelineSendPrep? prep,
    String? caption,
    required void Function(FileSendProgress p) onProgress,
  }) {
    return conversationService.sendTimelineAttachment(
      roomId: roomId,
      originalFilePath: originalFilePath,
      prep: prep,
      caption: caption,
      onProgress: onProgress,
    );
  }

  Future<void> cancelTimelineFileSend() {
    return conversationService.cancelTimelineFileSend();
  }

  Future<Uint8List?> fetchRoomMessageMedia({
    required String roomId,
    required String eventId,
    bool thumbnail = true,
  }) async {
    if (eventId.isEmpty) return null;
    final r = await conversationService.fetchRoomMessageMedia(
      roomId: roomId,
      eventId: eventId,
      thumbnail: thumbnail,
    );
    return r.fold((b) => b, (_) => null);
  }

  Future<void> retryFailedSend(String roomId, String transactionId) {
    return conversationService.retryFailedSend(
      roomId: roomId,
      transactionId: transactionId,
    );
  }

  /// Full message list from Rust on every change (no delta merge in Dart).
  Stream<List<Message>> subscribeToTimelineList(String roomId) {
    return conversationService.subscribeToTimelineList(roomId);
  }

  Future<void> roomListSubscribeToRooms(String roomId) {
    return conversationService.roomListSubscribeToRooms(roomId);
  }

  Future<Result<String>> acceptInvite(String roomId) {
    return conversationService.acceptInvite(roomId);
  }

  Future<Result<String>> rejectInvite(String roomId) {
    return conversationService.rejectInvite(roomId);
  }

  Future<Result<List<Message>>> fetchOlderMessages({
    required String conversationId,
    int count = 50,
  }) async {
    final messages = await conversationService.fetchOlderMessages(
      roomId: conversationId,
      count: count,
    );
    return messages;
  }

  Future<Result<Unit>> sendPoll({
    required String roomId,
    required String question,
    required List<String> answerTexts,
    required bool kindDisclosed,
    int maxSelections = 1,
  }) {
    return conversationService.sendPoll(
      roomId: roomId,
      question: question,
      answerTexts: answerTexts,
      kindDisclosed: kindDisclosed,
      maxSelections: maxSelections,
    );
  }

  Future<Result<Unit>> sendPollResponse({
    required String roomId,
    required String pollStartEventId,
    required List<String> answerIds,
  }) {
    return conversationService.sendPollResponse(
      roomId: roomId,
      pollStartEventId: pollStartEventId,
      answerIds: answerIds,
    );
  }
}

class ConversationScreenWM
    extends BaseWidgetModel<ConversationScreen, ConversationScreenModel> {
  ConversationScreenWM(super.model);
  late final ValueNotifier<ConversationState> _roomState;
  late final ValueNotifier<bool> _isInvited;
  late final TextEditingController _messageController;
  final ValueNotifier<bool> showPendingOutgoingInvite =
      ValueNotifier<bool>(false);

  ValueNotifier<ConversationState> get roomState => _roomState;
  TextEditingController get messageController => _messageController;
  ValueNotifier<bool> get isInvited => _isInvited;

  /// Non-null while a file send is in progress (shows banner + cancel).
  ValueNotifier<FileSendProgress?> get fileSendProgress => _fileSendProgress;

  // Stream status getters
  bool get isStreamActive => _isStreamActive;
  bool get isReconnecting => _reconnectionTimer != null;

  bool _disposed = false;

  final ValueNotifier<FileSendProgress?> _fileSendProgress =
      ValueNotifier<FileSendProgress?>(null);

  /// Set from room info to scroll the timeline to an event id.
  final ValueNotifier<String?> jumpToTimelineEventId = ValueNotifier<String?>(
    null,
  );

  /// Message the user is replying to (swipe message row); cleared after send or cancel.
  final ValueNotifier<Message?> replyDraft = ValueNotifier<Message?>(null);

  // Stream management: full message list from Rust
  StreamSubscription<List<Message>>? _timelineListSubscription;
  ConversationInfo? _roomInfo;
  Timer? _roomMetaDebounce;
  Timer? _reconnectionTimer;
  Timer? _healthCheckTimer;
  bool _isStreamActive = false;
  DateTime _lastUpdateTime = DateTime.now();

  // Reconnection settings
  static const Duration _reconnectionDelay = Duration(seconds: 5);
  static const Duration _healthCheckInterval = Duration(minutes: 2);
  static const Duration _maxInactivityTime = Duration(minutes: 5);

  @override
  void initWidgetModel() {
    super.initWidgetModel();
    _messageController = TextEditingController();
    _roomState = ValueNotifier(const ConversationState.loading());
    _isInvited = ValueNotifier(false);

    if (widget.status == ChatRoomStatus.invited) {
      _roomState.value = const ConversationState.waitingForInvite();
      _isInvited.value = true;
    } else {
      _loadMessages();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _listenToChatUpdates();
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  void dispose() {
    MatrixService().unregisterTimelineSubscription(widget.roomId);
    _disposeStreams();
    _roomState.dispose();
    _messageController.dispose();
    _isInvited.dispose();
    showPendingOutgoingInvite.dispose();
    _roomMetaDebounce?.cancel();
    _fileSendProgress.dispose();
    jumpToTimelineEventId.dispose();
    replyDraft.dispose();
    _disposed = true;
    super.dispose();
  }

  void _disposeStreams() {
    _timelineListSubscription?.cancel();
    _timelineListSubscription = null;
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    _isStreamActive = false;
  }

  /// Decrypted media for timeline previews in this room.
  /// [eventOrTransactionId] is [Message.eventId] or local-echo [Message.transactionId].
  Future<Uint8List?> fetchRoomMessageMedia(
    String eventOrTransactionId, {
    bool thumbnail = true,
  }) {
    return model.fetchRoomMessageMedia(
      roomId: widget.roomId,
      eventId: eventOrTransactionId,
      thumbnail: thumbnail,
    );
  }

  Future<void> openAttachment(Message message) async {
    if (message.isRedacted) return;
    if (TimelineLocalHiddenStore.isHidden(message)) return;
    if (message.roomMsgKind == RoomMessageKind.poll) return;
    final id = message.eventId.isNotEmpty
        ? message.eventId
        : message.transactionId;
    if (id.isEmpty) return;
    if (!context.mounted) return;
    await AttachmentViewer.open(
      context,
      loadFullBytes: () => fetchRoomMessageMedia(id, thumbnail: false),
      filename: message.content,
      roomMsgKind: message.roomMsgKind,
    );
  }

  Future<void> _loadMessages() async {
    _roomState.value = const ConversationState.loading();

    try {
      await TimelineLocalHiddenStore.ensureLoaded();
    } catch (_) {
      // Still show chat if prefs fail
    }
    try {
      _roomInfo = await model.loadRoomInfo(widget.roomId);
    } catch (_) {
      _roomInfo = ConversationInfo(
        id: widget.roomId,
        name: widget.roomName,
        topic: '',
        memberCount: 0,
      );
    }
    _syncPendingOutgoingInviteFromRoomInfo();
    _listenToChatUpdates();
  }

  /// Direct room you created: only you are joined until the invitee accepts.
  bool _shouldShowPendingOutgoingInvite(ConversationInfo info) {
    if (widget.status != ChatRoomStatus.joined) return false;
    if (!info.isDirect) return false;
    if (info.memberCount != 1) return false;
    if (Chat.isArchivedDirectRoomDisplayName(info.name)) return false;
    return true;
  }

  void _syncPendingOutgoingInviteFromRoomInfo() {
    final info = _roomInfo;
    if (info == null) {
      showPendingOutgoingInvite.value = false;
      return;
    }
    showPendingOutgoingInvite.value = _shouldShowPendingOutgoingInvite(info);
  }

  void _scheduleRoomMetaRefresh() {
    if (widget.status != ChatRoomStatus.joined) return;
    _roomMetaDebounce?.cancel();
    _roomMetaDebounce = Timer(const Duration(milliseconds: 500), () {
      if (_disposed) return;
      unawaited(_refreshRoomMeta());
    });
  }

  Future<void> _refreshRoomMeta() async {
    if (_disposed || widget.status != ChatRoomStatus.joined) {
      if (!_disposed) showPendingOutgoingInvite.value = false;
      return;
    }
    try {
      final info = await model.loadRoomInfo(widget.roomId);
      if (_disposed) return;
      _roomInfo = info;
      showPendingOutgoingInvite.value = _shouldShowPendingOutgoingInvite(info);
      _roomState.value.maybeWhen(
        loaded: (msgs, _) {
          _roomState.value = ConversationState.loaded(
            messages: msgs,
            roomInfo: info,
          );
        },
        orElse: () {},
      );
    } catch (_) {
      if (!_disposed) showPendingOutgoingInvite.value = false;
    }
  }

  void showMessageActionsMenu(BuildContext context, Message message) {
    if (message.messageType != MessageType.message ||
        message.isRedacted ||
        TimelineLocalHiddenStore.isHidden(message)) {
      return;
    }
    final canReply = message.eventId.isNotEmpty;
    final canReact =
        message.eventId.isNotEmpty || message.transactionId.isNotEmpty;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: MatrixTheme.terminalBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        side: BorderSide(color: MatrixTheme.terminalBorder),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(
                  'Reply',
                  style: TextStyle(fontFamily: MatrixTheme.fontFamily),
                ),
                enabled: canReply,
                onTap: canReply
                    ? () {
                        Navigator.pop(ctx);
                        beginReplyTo(message);
                      }
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: Text(
                  'React',
                  style: TextStyle(fontFamily: MatrixTheme.fontFamily),
                ),
                enabled: canReact,
                onTap: canReact
                    ? () {
                        Navigator.pop(ctx);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!context.mounted) return;
                          openTimelineQuickReactionPicker(
                            context,
                            onToggle: (k) => toggleTimelineReaction(message, k),
                          );
                        });
                      }
                    : null,
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  'Delete…',
                  style: TextStyle(
                    fontFamily: MatrixTheme.fontFamily,
                    color: theme.colorScheme.error,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    _showDeleteMessageChoices(context, message);
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteMessageChoices(BuildContext context, Message message) {
    final hasServerId = message.eventId.isNotEmpty;
    if (!hasServerId) {
      unawaited(_confirmHideMessageLocally(context, message));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: MatrixTheme.terminalBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        side: BorderSide(color: MatrixTheme.terminalBorder),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Remove message',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: MatrixTheme.fontFamily,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ListTile(
                title: Text(
                  'Delete for me',
                  style: TextStyle(fontFamily: MatrixTheme.fontFamily),
                ),
                subtitle: Text(
                  'Hide on this device only',
                  style: theme.textTheme.bodySmall,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_deleteMessageForMe(message));
                },
              ),
              ListTile(
                title: Text(
                  'Delete for everyone',
                  style: TextStyle(
                    fontFamily: MatrixTheme.fontFamily,
                    color: theme.colorScheme.error,
                  ),
                ),
                subtitle: Text(
                  'Redact for all members (if allowed)',
                  style: theme.textTheme.bodySmall,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_confirmRedactForEveryone(context, message));
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmHideMessageLocally(
    BuildContext context,
    Message message,
  ) async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              'Hide message?',
              style: TextStyle(fontFamily: MatrixTheme.fontFamily),
            ),
            content: const Text(
              'This message will be hidden on this device only.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Hide'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await _deleteMessageForMe(message);
  }

  Future<void> _confirmRedactForEveryone(
    BuildContext context,
    Message message,
  ) async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              'Delete for everyone?',
              style: TextStyle(fontFamily: MatrixTheme.fontFamily),
            ),
            content: const Text(
              'This sends a redaction so the message is removed for all room members (subject to your power level).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;
    final r = await model.redactTimelineEvent(
      roomId: widget.roomId,
      eventId: message.eventId,
      transactionId: message.transactionId,
    );
    if (!context.mounted) return;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    r.fold(
      (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: scheme.inverseSurface,
            content: Text(
              'Message redacted',
              style: TextStyle(
                color: scheme.onInverseSurface,
                fontFamily: MatrixTheme.fontFamily,
              ),
            ),
          ),
        );
      },
      (f) {
        final msg = _userVisibleFailureMessage(f);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: scheme.error,
            content: Text(
              msg.isEmpty ? 'Could not delete message' : msg,
              style: TextStyle(
                color: scheme.onError,
                fontFamily: MatrixTheme.fontFamily,
              ),
            ),
          ),
        );
      },
    );
  }

  static String _userVisibleFailureMessage(Object f) {
    final t = f.toString().trim();
    if (t.isEmpty || t == 'Exception') return '';
    return t.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  }

  Future<void> _deleteMessageForMe(Message message) async {
    await TimelineLocalHiddenStore.hideMessage(message);
  }

  /// Swipe a message row (horizontal) to start inline reply (needs a server event id).
  void beginReplyTo(Message message) {
    if (message.eventId.isEmpty) return;
    if (message.messageType != MessageType.message) return;
    if (message.isRedacted) return;
    if (TimelineLocalHiddenStore.isHidden(message)) return;
    HapticFeedback.lightImpact();
    replyDraft.value = message;
  }

  void clearReplyDraft() {
    replyDraft.value = null;
  }

  Future<void> toggleTimelineReaction(Message message, String reactionKey) async {
    if (message.eventId.isEmpty && message.transactionId.isEmpty) return;
    if (message.isRedacted || TimelineLocalHiddenStore.isHidden(message)) {
      return;
    }
    try {
      await model.toggleTimelineReaction(
        roomId: widget.roomId,
        message: message,
        reactionKey: reactionKey,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reaction failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void showReactionReactorsSheet(
    BuildContext context,
    Message message,
    MessageReactionEntry entry,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.45,
          minChildSize: 0.25,
          maxChildSize: 0.85,
          builder: (ctx, scrollController) {
            return FutureBuilder<RoomDetails>(
              future: MatrixService().client.getRoomDetails(
                roomId: widget.roomId,
              ),
              builder: (fbCtx, snapshot) {
                final theme = Theme.of(fbCtx);
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final rawOwn = snapshot.data?.currentUserId;
                final ownId =
                    rawOwn != null && rawOwn.isNotEmpty ? rawOwn : null;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        '${entry.key}  ·  ${entry.count}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: entry.senders.length,
                        itemBuilder: (ctx, i) {
                          final u = entry.senders[i];
                          final isSelf =
                              ownId != null && ownId.isNotEmpty && u == ownId;
                          return ListTile(
                            leading: Icon(
                              Icons.person_outline,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            title: Text(u),
                            trailing: isSelf
                                ? IconButton(
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 22,
                                      color: theme.colorScheme.error,
                                    ),
                                    tooltip: 'Remove reaction',
                                    onPressed: () async {
                                      Navigator.of(ctx).pop();
                                      await toggleTimelineReaction(
                                        message,
                                        entry.key,
                                      );
                                    },
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    final replyTarget = replyDraft.value;
    final replyToEventId = replyTarget != null && replyTarget.eventId.isNotEmpty
        ? replyTarget.eventId
        : null;

    try {
      final result = await model.sendMessage(
        widget.roomId,
        content,
        replyToEventId: replyToEventId,
      );
      result.fold((eventId) {
        _messageController.clear();
        clearReplyDraft();
        // Room list is updated in Rust on send; no need to push from Flutter.
      }, (_) {});
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  bool get showPollComposer {
    return _roomState.value.maybeWhen(
      loaded: (msgs, ri) => !ri.isDirect,
      orElse: () => false,
    );
  }

  Future<void> showCreatePollDialog() async {
    if (!context.mounted || !showPollComposer) return;
    final qCtrl = TextEditingController();
    final answerCtrls = <TextEditingController>[
      TextEditingController(),
      TextEditingController(),
    ];
    var disclosed = false;
    var maxSel = 1;
    bool? submitted;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
          final h = MediaQuery.sizeOf(ctx).height * 0.92;
          return Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SizedBox(
                height: h,
                child: StatefulBuilder(
                  builder: (ctx, setSt) {
                    void addOption() {
                      if (answerCtrls.length >= 12) return;
                      setSt(() => answerCtrls.add(TextEditingController()));
                    }

                    void removeOption(int i) {
                      if (answerCtrls.length <= 2) return;
                      setSt(() {
                        final removed = answerCtrls.removeAt(i);
                        maxSel = maxSel.clamp(1, answerCtrls.length);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          removed.dispose();
                        });
                      });
                    }

                    final nAnswers = answerCtrls.length;
                    final maxSelItems = List.generate(
                      nAnswers,
                      (i) => i + 1,
                    );

                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: MatrixTheme.terminalBlack.withValues(alpha: 0.98),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        border: Border.all(
                          color: MatrixTheme.matrixGreen.withValues(alpha: 0.4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: MatrixTheme.matrixAccent.withValues(
                              alpha: 0.12,
                            ),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 10),
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: MatrixTheme.matrixDarkGreen.withValues(
                                  alpha: 0.55,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '> COMPOSE // POLL',
                                    style: TextStyle(
                                      color: MatrixTheme.matrixLightGreen,
                                      fontFamily: MatrixTheme.fontFamily,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  color: MatrixTheme.matrixGreen,
                                  tooltip: 'Close',
                                  onPressed: () => Navigator.pop(ctx),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                              children: [
                                Text(
                                  'Question',
                                  style: TextStyle(
                                    color: MatrixTheme.matrixDarkGreen
                                        .withValues(alpha: 0.9),
                                    fontFamily: MatrixTheme.fontFamily,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: qCtrl,
                                  maxLines: 3,
                                  style: TextStyle(
                                    color: MatrixTheme.matrixLightGreen,
                                    fontFamily: MatrixTheme.fontFamily,
                                  ),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: MatrixTheme.terminalBackground
                                        .withValues(alpha: 0.9),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(4),
                                      borderSide: BorderSide(
                                        color: MatrixTheme.matrixGreen
                                            .withValues(alpha: 0.45),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(4),
                                      borderSide: BorderSide(
                                        color: MatrixTheme.matrixGreen
                                            .withValues(alpha: 0.35),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    Text(
                                      'Answers',
                                      style: TextStyle(
                                        color: MatrixTheme.matrixDarkGreen
                                            .withValues(alpha: 0.9),
                                        fontFamily: MatrixTheme.fontFamily,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: addOption,
                                      icon: Icon(
                                        Icons.add,
                                        size: 18,
                                        color: MatrixTheme.matrixAccent,
                                      ),
                                      label: Text(
                                        'Add',
                                        style: TextStyle(
                                          color: MatrixTheme.matrixAccent,
                                          fontFamily: MatrixTheme.fontFamily,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ...List.generate(answerCtrls.length, (i) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: answerCtrls[i],
                                            style: TextStyle(
                                              color:
                                                  MatrixTheme.matrixLightGreen,
                                              fontFamily:
                                                  MatrixTheme.fontFamily,
                                            ),
                                            decoration: InputDecoration(
                                              labelText: 'Option ${i + 1}',
                                              labelStyle: TextStyle(
                                                color: MatrixTheme.matrixGreen
                                                    .withValues(alpha: 0.7),
                                                fontFamily:
                                                    MatrixTheme.fontFamily,
                                                fontSize: 12,
                                              ),
                                              filled: true,
                                              fillColor: MatrixTheme
                                                  .terminalBackground
                                                  .withValues(alpha: 0.85),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                borderSide: BorderSide(
                                                  color: MatrixTheme.matrixGreen
                                                      .withValues(alpha: 0.35),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (answerCtrls.length > 2)
                                          IconButton(
                                            onPressed: () => removeOption(i),
                                            icon: Icon(
                                              Icons.remove_circle_outline,
                                              color: MatrixTheme.warningOrange
                                                  .withValues(alpha: 0.85),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }),
                                const SizedBox(height: 12),
                                Text(
                                  'Result visibility',
                                  style: TextStyle(
                                    color: MatrixTheme.matrixDarkGreen
                                        .withValues(alpha: 0.9),
                                    fontFamily: MatrixTheme.fontFamily,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: MatrixTheme.matrixGreen
                                          .withValues(alpha: 0.35),
                                    ),
                                    color: MatrixTheme.terminalBackground
                                        .withValues(alpha: 0.75),
                                  ),
                                  child: Column(
                                    children: [
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () =>
                                              setSt(() => disclosed = false),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              border: Border(
                                                left: BorderSide(
                                                  color: !disclosed
                                                      ? MatrixTheme.matrixAccent
                                                      : Colors.transparent,
                                                  width: 3,
                                                ),
                                              ),
                                              color: !disclosed
                                                  ? MatrixTheme.matrixAccent
                                                      .withValues(alpha: 0.08)
                                                  : null,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Undisclosed',
                                                  style: TextStyle(
                                                    color: MatrixTheme
                                                        .matrixLightGreen,
                                                    fontFamily:
                                                        MatrixTheme.fontFamily,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Counts stay hidden until the poll is closed.',
                                                  style: TextStyle(
                                                    color: MatrixTheme
                                                        .matrixDarkGreen
                                                        .withValues(alpha: 0.95),
                                                    fontFamily:
                                                        MatrixTheme.fontFamily,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Divider(
                                        height: 1,
                                        color: MatrixTheme.matrixGreen
                                            .withValues(alpha: 0.2),
                                      ),
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () =>
                                              setSt(() => disclosed = true),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              border: Border(
                                                left: BorderSide(
                                                  color: disclosed
                                                      ? MatrixTheme.matrixAccent
                                                      : Colors.transparent,
                                                  width: 3,
                                                ),
                                              ),
                                              color: disclosed
                                                  ? MatrixTheme.matrixAccent
                                                      .withValues(alpha: 0.08)
                                                  : null,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Disclosed',
                                                  style: TextStyle(
                                                    color: MatrixTheme
                                                        .matrixLightGreen,
                                                    fontFamily:
                                                        MatrixTheme.fontFamily,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Show who voted for each option as votes arrive.',
                                                  style: TextStyle(
                                                    color: MatrixTheme
                                                        .matrixDarkGreen
                                                        .withValues(alpha: 0.95),
                                                    fontFamily:
                                                        MatrixTheme.fontFamily,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Text(
                                      'Max selections per voter',
                                      style: TextStyle(
                                        color: MatrixTheme.matrixLightGreen,
                                        fontFamily: MatrixTheme.fontFamily,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const Spacer(),
                                    DropdownButton<int>(
                                      value: maxSel.clamp(1, nAnswers),
                                      dropdownColor:
                                          MatrixTheme.terminalBlack,
                                      style: TextStyle(
                                        color: MatrixTheme.matrixAccent,
                                        fontFamily: MatrixTheme.fontFamily,
                                      ),
                                      items: maxSelItems
                                          .map(
                                            (e) => DropdownMenuItem(
                                              value: e,
                                              child: Text('$e'),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => setSt(
                                        () => maxSel = v ?? 1,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              MatrixTheme.matrixGreen,
                                          side: BorderSide(
                                            color: MatrixTheme.matrixGreen
                                                .withValues(alpha: 0.5),
                                          ),
                                        ),
                                        child: Text(
                                          'Cancel',
                                          style: TextStyle(
                                            fontFamily: MatrixTheme.fontFamily,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: () {
                                          submitted = true;
                                          Navigator.pop(ctx);
                                        },
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              MatrixTheme.matrixAccent,
                                          foregroundColor:
                                              MatrixTheme.terminalBlack,
                                        ),
                                        child: Text(
                                          'Send poll',
                                          style: TextStyle(
                                            fontFamily: MatrixTheme.fontFamily,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
      if (submitted != true || !context.mounted) return;
      final question = qCtrl.text.trim();
      final answers = answerCtrls
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (question.isEmpty || answers.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a question and at least two answers'),
          ),
        );
        return;
      }
      final r = await model.sendPoll(
        roomId: widget.roomId,
        question: question,
        answerTexts: answers,
        kindDisclosed: disclosed,
        maxSelections: maxSel.clamp(1, answers.length),
      );
      if (!context.mounted) return;
      r.fold(
        (_) => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Poll sent')),
        ),
        (f) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $f'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        ),
      );
    } finally {
      // Pop completes before the sheet route finishes tearing down; disposing
      // here triggers "used after disposed" on the sheet's TextFields.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        qCtrl.dispose();
        for (final c in answerCtrls) {
          c.dispose();
        }
      });
    }
  }

  Future<void> voteOnPoll(
    String pollEventId,
    List<String> answerIds,
  ) async {
    if (pollEventId.isEmpty || answerIds.isEmpty) return;
    final r = await model.sendPollResponse(
      roomId: widget.roomId,
      pollStartEventId: pollEventId,
      answerIds: answerIds,
    );
    if (!context.mounted) return;
    r.fold(
      (_) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vote recorded')),
      ),
      (f) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vote failed: $f'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }

  /// Opens gallery (photos/videos) or system file picker, then sends the selection.
  Future<void> showAttachMenu() async {
    if (!context.mounted) return;
    final theme = Theme.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.photo_library_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Photo or video'),
                subtitle: const Text('From gallery'),
                onTap: () => Navigator.pop(sheetContext, 'gallery'),
              ),
              ListTile(
                leading: Icon(
                  Icons.folder_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('File'),
                subtitle: const Text('Browse files'),
                onTap: () => Navigator.pop(sheetContext, 'file'),
              ),
            ],
          ),
        );
      },
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'gallery') {
      await pickAndSendFromGallery();
    } else if (choice == 'file') {
      await pickAndSendFile();
    }
  }

  Future<void> pickAndSendFromGallery() async {
    if (kIsWeb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gallery attachments are not supported on web.'),
          ),
        );
      }
      return;
    }
    final picker = ImagePicker();
    final XFile? picked = await picker.pickMedia(imageQuality: 100);
    if (picked == null) return;
    final path = await _pathForGalleryPick(picked);
    if (path == null || path.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access the selected media.')),
        );
      }
      return;
    }
    await _sendTimelineFileFromPath(path, mimeType: picked.mimeType);
  }

  /// When the OS returns a content URI without a direct path, copy bytes to a temp file.
  Future<String?> _pathForGalleryPick(XFile x) async {
    final direct = x.path;
    if (direct.isNotEmpty) return direct;
    final bytes = await x.readAsBytes();
    if (bytes.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final rawName = x.name.trim();
    final name = rawName.isEmpty
        ? 'gallery_${DateTime.now().millisecondsSinceEpoch}'
        : path_lib.basename(rawName);
    final file = File(path_lib.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// When the picker returns no path (scoped storage) but [withData] supplied bytes.
  Future<String?> _pathForFilePick(PlatformFile file) async {
    final direct = file.path;
    if (direct != null && direct.isNotEmpty) return direct;
    if (kIsWeb) return null;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final rawName = file.name.trim();
    final name = rawName.isEmpty
        ? 'file_${DateTime.now().millisecondsSinceEpoch}'
        : path_lib.basename(rawName);
    final out = File(path_lib.join(dir.path, name));
    await out.writeAsBytes(bytes, flush: true);
    return out.path;
  }

  static String? _mimeByDottedExtension(String ext) {
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.webm':
        return 'video/webm';
      case '.pdf':
        return 'application/pdf';
      default:
        return null;
    }
  }

  String? _mimeForPickedFile(PlatformFile file, String resolvedPath) {
    final fromPicker = file.extension?.trim();
    if (fromPicker != null && fromPicker.isNotEmpty) {
      final dotted = fromPicker.startsWith('.')
          ? fromPicker.toLowerCase()
          : '.${fromPicker.toLowerCase()}';
      final m = _mimeByDottedExtension(dotted);
      if (m != null) return m;
    }
    return _mimeByDottedExtension(path_lib.extension(resolvedPath).toLowerCase());
  }

  Future<void> pickAndSendFile() async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: !kIsWeb,
    );
    if (pick == null || pick.files.isEmpty) return;
    if (!context.mounted) return;
    final platformFile = pick.files.single;
    final path = await _pathForFilePick(platformFile);
    if (path == null || path.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read the selected file.'),
          ),
        );
      }
      return;
    }
    final mime = _mimeForPickedFile(platformFile, path);
    await _sendTimelineFileFromPath(path, mimeType: mime);
  }

  Future<void> _sendTimelineFileFromPath(
    String path, {
    String? mimeType,
  }) async {
    final caption = _messageController.text.trim();
    if (!kIsWeb && context.mounted) {
      final ok = await Navigator.of(context, rootNavigator: true).push<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (ctx) => MediaOutgoingSendScreen(
            title: 'Send attachment',
            filePath: path,
            mimeType: mimeType,
            caption: caption.isEmpty ? null : caption,
            sendAttachment: ({
              prep,
              required originalFilePath,
              required onProgress,
            }) =>
                model.sendTimelineAttachment(
                  roomId: widget.roomId,
                  originalFilePath: originalFilePath,
                  prep: prep,
                  caption: caption.isEmpty ? null : caption,
                  onProgress: onProgress,
                ),
            onCancelSend: () {
              model.cancelTimelineFileSend();
            },
          ),
        ),
      );
      if (ok == true && !_disposed) {
        _messageController.clear();
      }
      return;
    }

    try {
      final result = await model.sendTimelineFileWithProgress(
        roomId: widget.roomId,
        filePath: path,
        caption: caption.isEmpty ? null : caption,
        mimeType: mimeType,
        onProgress: (p) {
          if (_disposed) return;
          final terminal =
              p.phase == FileSendPhase.done ||
              p.phase == FileSendPhase.failed ||
              p.phase == FileSendPhase.cancelled;
          _fileSendProgress.value = terminal ? null : p;
        },
      );
      result.fold((_) => _messageController.clear(), (failure) {
        if (context.mounted) {
          final msg = failure.toString();
          if (!msg.contains('Cancelled')) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to send file: $failure'),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        }
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send file: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (!_disposed) {
        _fileSendProgress.value = null;
      }
    }
  }

  void cancelFileSend() {
    model.cancelTimelineFileSend();
  }

  Future<void> showRoomInfo() async {
    if (!context.mounted) return;
    final result = await Navigator.of(context).push<RoomInfoNavResult?>(
      MaterialPageRoute(
        builder: (ctx) => RoomInfoScreen(
          roomId: widget.roomId,
          initialTitle: widget.roomName,
        ),
      ),
    );
    if (!context.mounted) return;
    if (result?.leftRoom == true) {
      NavigatorService.pop(context);
      return;
    }
    final focus = result?.focusEventId;
    if (focus != null && focus.isNotEmpty) {
      // Let the conversation route finish rebuilding after room info closes,
      // then notify so [PaginatedMessageList] sees the jump request reliably.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || _disposed) return;
        jumpToTimelineEventId.value = null;
        jumpToTimelineEventId.value = focus;
      });
    }
  }

  void retry() {
    _loadMessages();
  }

  Future<void> retryFailedSend(String transactionId) async {
    try {
      await model.retryFailedSend(widget.roomId, transactionId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Retry failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Same newest timeline row but fewer items → likely a stale VectorDiff reset behind pagination.
  static bool _isRegressiveTimelineList(
    List<Message> incoming,
    List<Message> previous,
  ) {
    if (previous.isEmpty || incoming.isEmpty) return false;
    if (incoming.length >= previous.length) return false;
    final a = incoming.last;
    final b = previous.last;
    if (a.eventId.isNotEmpty && b.eventId.isNotEmpty) {
      return a.eventId == b.eventId;
    }
    if (a.transactionId.isNotEmpty && b.transactionId.isNotEmpty) {
      return a.transactionId == b.transactionId;
    }
    return false;
  }

  void _listenToChatUpdates() {
    LoggingService.info(
      'CONVERSATION_SCREEN',
      'Starting timeline list subscription for room: ${widget.roomId}',
    );
    unawaited(model.roomListSubscribeToRooms(widget.roomId));
    _disposeStreams();
    MatrixService().cancelTimelineSubscriptionForRoom(widget.roomId);

    final roomInfo =
        _roomInfo ??
        ConversationInfo(
          id: widget.roomId,
          name: widget.roomName,
          topic: '',
          memberCount: 0,
        );

    _timelineListSubscription = model
        .subscribeToTimelineList(widget.roomId)
        .listen(
          (list) {
            if (_disposed) return;
            final prev = _roomState.value;
            if (prev is RoomStateLoaded) {
              if (list.isEmpty && prev.messages.isNotEmpty) {
                LoggingService.info(
                  'CONVERSATION_SCREEN',
                  'Ignoring empty timeline list (keeping ${prev.messages.length} messages)',
                );
                return;
              }
              if (_isRegressiveTimelineList(list, prev.messages)) {
                LoggingService.info(
                  'CONVERSATION_SCREEN',
                  'Ignoring regressive timeline snapshot (${list.length} < ${prev.messages.length}, same tail)',
                );
                return;
              }
            }
            _lastUpdateTime = DateTime.now();
            _isStreamActive = true;
            LoggingService.info(
              'CONVERSATION_SCREEN',
              'Received timeline list: ${list.length} messages',
            );
            _roomState.value = ConversationState.loaded(
              messages: list,
              roomInfo: _roomInfo ?? roomInfo,
            );
            _scheduleRoomMetaRefresh();
          },
          onError: (error) {
            LoggingService.error(
              'CONVERSATION_SCREEN',
              'Timeline list stream error: $error',
            );
            _isStreamActive = false;
            _scheduleReconnection();
          },
          onDone: () {
            LoggingService.info(
              'CONVERSATION_SCREEN',
              'Timeline list stream completed',
            );
            _isStreamActive = false;
            _scheduleReconnection();
          },
        );

    MatrixService().registerTimelineSubscription(
      widget.roomId,
      _timelineListSubscription!,
    );
    _startHealthCheck();
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }

      final timeSinceLastUpdate = DateTime.now().difference(_lastUpdateTime);
      LoggingService.info(
        'CONVERSATION_SCREEN',
        'Health check: Stream active: $_isStreamActive, Time since last update: ${timeSinceLastUpdate.inSeconds}s',
      );

      if (timeSinceLastUpdate > _maxInactivityTime) {
        LoggingService.info(
          'CONVERSATION_SCREEN',
          'Chat updates stream inactive for too long (${timeSinceLastUpdate.inMinutes} minutes), reconnecting...',
        );
        _isStreamActive = false;
        _scheduleReconnection();
      }
    });
  }

  Future<void> _restartSyncAndResubscribe() async {
    if (_disposed) return;
    try {
      await MatrixService().client.restartSyncService();
      if (!_disposed) _listenToChatUpdates();
    } catch (e) {
      LoggingService.error('CONVERSATION_SCREEN', 'Failed to restart sync: $e');
      if (!_disposed) _scheduleReconnection();
    }
  }

  void _scheduleReconnection() {
    if (_disposed || _reconnectionTimer != null) return;

    LoggingService.info(
      'CONVERSATION_SCREEN',
      'Scheduling reconnection in ${_reconnectionDelay.inSeconds} seconds...',
    );
    _reconnectionTimer = Timer(_reconnectionDelay, () {
      if (_disposed) return;

      LoggingService.info(
        'CONVERSATION_SCREEN',
        'Attempting to reconnect chat updates stream...',
      );
      _restartSyncAndResubscribe();
    });
  }

  void _forceReconnect() {
    if (_disposed) return;

    LoggingService.info(
      'CONVERSATION_SCREEN',
      'Force reconnecting chat updates stream...',
    );
    _listenToChatUpdates();
  }

  /// Manually reconnect the chat updates stream
  void reconnectStream() {
    if (_disposed) return;
    _forceReconnect();
  }

  /// Check if the stream is healthy and active
  bool isStreamHealthy() {
    if (_disposed) return false;

    final timeSinceLastUpdate = DateTime.now().difference(_lastUpdateTime);
    return _isStreamActive && timeSinceLastUpdate <= _maxInactivityTime;
  }

  /// Get a human-readable status of the stream connection
  String getStreamStatus() {
    if (_disposed) return 'Disposed';
    if (_isStreamActive && isStreamHealthy()) return 'Connected';
    if (_reconnectionTimer != null) return 'Reconnecting...';
    if (!_isStreamActive) return 'Disconnected';
    return 'Unknown';
  }

  Future<void> acceptInvite() async {
    final result = await model.acceptInvite(widget.roomId);
    if (result.isSuccess()) {
      _isInvited.value = false;
      _loadMessages();
    }
  }

  Future<void> rejectInvite() async {
    final result = await model.rejectInvite(widget.roomId);
    if (result.isSuccess() && context.mounted) {
      widget.goBack(context);
    }
  }

  /// Fetches older messages (paginates backwards) and updates room state with
  /// the full timeline. Returns (newly loaded chunk for scroll, hasMore).
  /// When the SDK returns the full list we update state and return ([], hasMore).
  Future<(List<Message>, bool)> fetchOlderMessages({
    required String conversationId,
    int limit = 50,
  }) async {
    final currentState = roomState.value;
    if (currentState is! RoomStateLoaded) {
      return (List<Message>.from([]), false);
    }

    final result = await model.fetchOlderMessages(
      conversationId: conversationId,
      count: limit,
    );

    return result.fold((fullList) {
      final previousLength = currentState.messages.length;
      _roomState.value = currentState.copyWith(messages: fullList);
      final atTimelineStart =
          fullList.isNotEmpty &&
          fullList.first.messageType == MessageType.timelineStart;
      final hasMore = !atTimelineStart && fullList.length > previousLength;
      return (List<Message>.from([]), hasMore);
    }, (failure) => (List<Message>.from([]), false));
  }
}
