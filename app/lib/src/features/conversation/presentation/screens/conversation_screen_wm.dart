import 'dart:async';
import 'dart:io';

import 'package:elementary/elementary.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/src/core/desktop/desktop_camera_flow.dart';
import 'package:matrix/src/core/desktop/desktop_esc_scope.dart';
import 'package:matrix/src/core/desktop/desktop_shell_scope.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/timeline_local_hidden_store.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/settings/domain/profile_prefs.dart';
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
import 'package:matrix/src/features/conversation/presentation/widgets/voice_record_sheet.dart';
import 'package:matrix/src/features/conversation/presentation/widgets/pagianted_message_list.dart'
    show openTimelineQuickReactionPicker;
import 'package:matrix_sdk/matrix_sdk.dart'
    show
        EventSendStateKind,
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

  Future<Result<({ConversationInfo info, RoomDetails details})>> loadRoomSnapshot(
    String roomId,
  ) {
    return conversationService.loadRoomSnapshot(roomId);
  }

  Future<Result<RoomDetails>> getRoomDetails(String roomId) {
    return conversationService.getRoomDetails(roomId);
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
    int? audioDurationMs,
    List<double>? audioWaveformNormalized,
    bool audioAsVoiceMessage = false,
    required void Function(FileSendProgress p) onProgress,
  }) {
    return conversationService.sendTimelineFileWithProgress(
      roomId: roomId,
      filePath: filePath,
      caption: caption,
      mimeType: mimeType,
      audioDurationMs: audioDurationMs,
      audioWaveformNormalized: audioWaveformNormalized,
      audioAsVoiceMessage: audioAsVoiceMessage,
      onProgress: onProgress,
    );
  }

  Future<Result<Unit>> sendTimelineAttachment({
    required String roomId,
    required String originalFilePath,
    AppTimelineSendPrep? prep,
    String? caption,
    int? audioDurationMs,
    List<double>? audioWaveformNormalized,
    bool audioAsVoiceMessage = false,
    required void Function(FileSendProgress p) onProgress,
  }) {
    return conversationService.sendTimelineAttachment(
      roomId: roomId,
      originalFilePath: originalFilePath,
      prep: prep,
      caption: caption,
      audioDurationMs: audioDurationMs,
      audioWaveformNormalized: audioWaveformNormalized,
      audioAsVoiceMessage: audioAsVoiceMessage,
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

  Future<Uint8List?> fetchUserAvatarThumbnail(String mxcUri) async {
    final t = mxcUri.trim();
    if (t.isEmpty) return null;
    final r = await conversationService.fetchUserAvatarThumbnail(mxcUri: t);
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

  Future<void> markTimelineAsRead(String roomId) {
    return conversationService.markTimelineAsRead(roomId);
  }
}

class ConversationScreenWM
    extends BaseWidgetModel<ConversationScreen, ConversationScreenModel> {
  ConversationScreenWM(super.model);
  late final ValueNotifier<ConversationState> _roomState;
  late final ValueNotifier<bool> _isInvited;
  late final TextEditingController _messageController;
  final ValueNotifier<bool> showPendingOutgoingInvite = ValueNotifier<bool>(
    false,
  );

  ValueNotifier<ConversationState> get roomState => _roomState;
  TextEditingController get messageController => _messageController;
  ValueNotifier<bool> get isInvited => _isInvited;

  /// `true` when the composer has non-whitespace text (send vs voice-record button).
  ValueNotifier<bool> get composerHasText => _composerHasText;

  /// Primary message field; focused when the timeline first reaches [ConversationState.loaded].
  FocusNode get composerFocusNode => _composerFocusNode;

  /// Non-null while a file send is in progress (shows banner + cancel).
  ValueNotifier<FileSendProgress?> get fileSendProgress => _fileSendProgress;

  // Stream status getters
  bool get isStreamActive => _isStreamActive;
  bool get isReconnecting => _reconnectionTimer != null;

  bool _disposed = false;

  final ValueNotifier<FileSendProgress?> _fileSendProgress =
      ValueNotifier<FileSendProgress?>(null);

  final ValueNotifier<bool> _composerHasText = ValueNotifier<bool>(false);

  final FocusNode _composerFocusNode = FocusNode(debugLabel: 'messageComposer');

  ConversationState? _prevRoomStateForComposerFocus;

  void _onRoomStateForComposerFocus() {
    if (_disposed) return;
    final next = _roomState.value;
    final prev = _prevRoomStateForComposerFocus;
    _prevRoomStateForComposerFocus = next;

    final nextLoaded = next.maybeWhen(
      loaded: (_, __) => true,
      orElse: () => false,
    );
    if (!nextLoaded) return;

    final prevLoaded =
        prev?.maybeWhen(loaded: (_, __) => true, orElse: () => false) ?? false;
    if (prevLoaded) return;

    if (_isInvited.value) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !context.mounted || _isInvited.value) return;
      // Auto-focus composer only on desktop; on phones it traps the software keyboard.
      if (!isDesktopTargetPlatform()) return;
      _composerFocusNode.requestFocus();
    });
  }

  /// Set from room info to scroll the timeline to an event id.
  final ValueNotifier<String?> jumpToTimelineEventId = ValueNotifier<String?>(
    null,
  );

  /// Current member avatars (`mxc://…`) keyed by Matrix user id; refreshes with room meta so
  /// timeline bubbles pick up profile photo changes without re-fetching every event row.
  final ValueNotifier<Map<String, String>> senderAvatarMxcByUserId =
      ValueNotifier<Map<String, String>>(<String, String>{});

  /// Debounces [markTimelineAsRead] so scroll / timeline bursts do not spam the homeserver.
  Timer? _markReadDebounce;

  /// Message the user is replying to (e.g. from ⋮ menu); cleared after send or cancel.
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

  void _syncComposerHasText() {
    _composerHasText.value = _messageController.text.trim().isNotEmpty;
  }

  @override
  void initWidgetModel() {
    super.initWidgetModel();
    _messageController = TextEditingController();
    _messageController.addListener(_syncComposerHasText);
    _roomState = ValueNotifier(const ConversationState.loading());
    _isInvited = ValueNotifier(false);
    _prevRoomStateForComposerFocus = _roomState.value;
    _roomState.addListener(_onRoomStateForComposerFocus);

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
    _roomState.removeListener(_onRoomStateForComposerFocus);
    _roomState.dispose();
    _messageController.removeListener(_syncComposerHasText);
    _messageController.dispose();
    _composerFocusNode.dispose();
    _composerHasText.dispose();
    _isInvited.dispose();
    showPendingOutgoingInvite.dispose();
    _roomMetaDebounce?.cancel();
    _markReadDebounce?.cancel();
    _fileSendProgress.dispose();
    jumpToTimelineEventId.dispose();
    replyDraft.dispose();
    senderAvatarMxcByUserId.dispose();
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

  Future<Uint8List?> fetchUserAvatarThumbnail(String mxcUri) {
    return model.fetchUserAvatarThumbnail(mxcUri);
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
      mediaMimetype: message.mediaMimetype,
    );
  }

  Future<void> _loadMessages() async {
    // Isolates: timeline/room data comes from Rust via FFI and [Message]/[RoomDetails]
    // are not sendable across isolates; SharedPreferences uses the platform channel on
    // the root isolate. Heavy lifting stays native/async — we avoid duplicate Rust calls
    // and overlap independent futures instead.
    final hiddenFuture = TimelineLocalHiddenStore.ensureLoaded().catchError((_) {});
    final roomSnapshotFuture = model.loadRoomSnapshot(widget.roomId);
    final messagesFuture = model.loadMessages(widget.roomId);

    await hiddenFuture;

    try {
      final roomRes = await roomSnapshotFuture;
      roomRes.fold(
        (snap) {
          _roomInfo = snap.info;
          if (!_disposed) {
            _applyMemberAvatarOverridesFromDetails(snap.details);
          }
        },
        (_) {
          _roomInfo = ConversationInfo(
            id: widget.roomId,
            name: widget.roomName,
            topic: '',
            memberCount: 0,
          );
        },
      );
    } catch (_) {
      _roomInfo = ConversationInfo(
        id: widget.roomId,
        name: widget.roomName,
        topic: '',
        memberCount: 0,
      );
    }
    _syncPendingOutgoingInviteFromRoomInfo();

    // One-shot timeline from Rust (same cache the stream will use) so split-view
    // switches paint messages immediately instead of a long "loading" state.
    try {
      final snap = await messagesFuture;
      snap.fold(
        (list) {
          if (_disposed) return;
          _roomState.value = ConversationState.loaded(
            messages: list,
            roomInfo: _roomInfo!,
          );
          _lastUpdateTime = DateTime.now();
        },
        (_) {
          if (!_disposed) {
            _roomState.value = const ConversationState.loading();
          }
        },
      );
    } catch (_) {
      if (!_disposed) {
        _roomState.value = const ConversationState.loading();
      }
    }

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

  /// Coalesces [markTimelineAsRead] while the timeline stream emits rapid diffs.
  void _scheduleMarkTimelineRead() {
    if (widget.status != ChatRoomStatus.joined) return;
    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(const Duration(milliseconds: 400), () {
      if (_disposed) return;
      unawaited(model.markTimelineAsRead(widget.roomId).catchError((_) {}));
    });
  }

  /// When the user scrolls back to the newest messages, send a read receipt for the latest event.
  void onTimelineScrolledToBottom() => _scheduleMarkTimelineRead();

  void _scheduleRoomMetaRefresh() {
    if (widget.status != ChatRoomStatus.joined) return;
    _roomMetaDebounce?.cancel();
    _roomMetaDebounce = Timer(const Duration(milliseconds: 500), () {
      if (_disposed) return;
      unawaited(_refreshRoomMeta());
    });
  }

  void _applyMemberAvatarOverridesFromDetails(RoomDetails d) {
    if (_disposed) return;
    final map = <String, String>{};
    for (final m in d.members) {
      final a = m.avatarUrl.trim();
      if (a.isNotEmpty) {
        map[m.userId] = a;
      }
    }
    senderAvatarMxcByUserId.value = map;
  }

  Future<void> _refreshRoomMeta() async {
    if (_disposed || widget.status != ChatRoomStatus.joined) {
      if (!_disposed) showPendingOutgoingInvite.value = false;
      return;
    }
    try {
      final snapRes = await model.loadRoomSnapshot(widget.roomId);
      if (_disposed) return;
      snapRes.fold(
        (snap) {
          _roomInfo = snap.info;
          showPendingOutgoingInvite.value =
              _shouldShowPendingOutgoingInvite(snap.info);
          _applyMemberAvatarOverridesFromDetails(snap.details);
          _roomState.value.maybeWhen(
            loaded: (msgs, _) {
              _roomState.value = ConversationState.loaded(
                messages: msgs,
                roomInfo: snap.info,
              );
            },
            orElse: () {},
          );
        },
        (_) {
          if (!_disposed) showPendingOutgoingInvite.value = false;
        },
      );
    } catch (_) {
      if (!_disposed) showPendingOutgoingInvite.value = false;
    }
  }

  void showMessageActionsMenu(
    BuildContext context,
    Message message,
    Offset anchorGlobal,
  ) {
    if (message.messageType != MessageType.message ||
        message.isRedacted ||
        TimelineLocalHiddenStore.isHidden(message)) {
      return;
    }
    final canReply = message.eventId.isNotEmpty;
    final canReact =
        message.eventId.isNotEmpty || message.transactionId.isNotEmpty;
    if (isDesktopTargetPlatform()) {
      final theme = Theme.of(context);
      unawaited(
        showMenu<void>(
          context: context,
          position: desktopMenuPositionAt(context, anchorGlobal),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.45),
            ),
          ),
          color: MatrixTheme.terminalBackground,
          items: [
            PopupMenuItem<void>(
              enabled: canReply,
              onTap: canReply
                  ? () {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!this.context.mounted) return;
                        beginReplyTo(message);
                      });
                    }
                  : null,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.reply_rounded, size: 22),
                title: Text(
                  'Reply',
                  style: TextStyle(fontFamily: MatrixTheme.fontFamily),
                ),
              ),
            ),
            PopupMenuItem<void>(
              enabled: canReact,
              onTap: canReact
                  ? () {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!this.context.mounted) return;
                        openTimelineQuickReactionPicker(
                          this.context,
                          onToggle: (k) => toggleTimelineReaction(message, k),
                        );
                      });
                    }
                  : null,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.emoji_emotions_outlined, size: 22),
                title: Text(
                  'React',
                  style: TextStyle(fontFamily: MatrixTheme.fontFamily),
                ),
              ),
            ),
            PopupMenuItem<void>(
              onTap: () {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!this.context.mounted) return;
                  _showDeleteMessageChoices(
                    this.context,
                    message,
                    anchorGlobal,
                  );
                });
              },
              child: ListTile(
                dense: true,
                leading: Icon(
                  Icons.delete_outline,
                  size: 22,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  'Delete…',
                  style: TextStyle(
                    fontFamily: MatrixTheme.fontFamily,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
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
                    _showDeleteMessageChoices(context, message, anchorGlobal);
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteMessageChoices(
    BuildContext context,
    Message message, [
    Offset? menuAnchor,
  ]) {
    final hasServerId = message.eventId.isNotEmpty;
    if (!hasServerId) {
      unawaited(_confirmHideMessageLocally(context, message));
      return;
    }
    if (isDesktopTargetPlatform()) {
      final theme = Theme.of(context);
      final pos =
          menuAnchor ??
          Offset(
            MediaQuery.sizeOf(context).width / 2,
            MediaQuery.paddingOf(context).top + 48,
          );
      unawaited(
        showMenu<void>(
          context: context,
          position: desktopMenuPositionAt(context, pos),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.45),
            ),
          ),
          color: MatrixTheme.terminalBackground,
          items: [
            PopupMenuItem<void>(
              onTap: () {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  unawaited(_deleteMessageForMe(message));
                });
              },
              child: ListTile(
                dense: true,
                title: Text(
                  'Delete for me',
                  style: TextStyle(fontFamily: MatrixTheme.fontFamily),
                ),
                subtitle: Text(
                  'Hide on this device only',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            PopupMenuItem<void>(
              onTap: () {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  unawaited(_confirmRedactForEveryone(context, message));
                });
              },
              child: ListTile(
                dense: true,
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
              ),
            ),
          ],
        ),
      );
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

  /// Start inline reply (needs a server event id); used from the message ⋮ menu.
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

  Future<void> toggleTimelineReaction(
    Message message,
    String reactionKey,
  ) async {
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
    if (isDesktopTargetPlatform()) {
      unawaited(_showReactionReactorsDesktopMenu(context, message, entry));
      return;
    }
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
                final ownId = rawOwn != null && rawOwn.isNotEmpty
                    ? rawOwn
                    : null;

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

  Future<void> _showReactionReactorsDesktopMenu(
    BuildContext context,
    Message message,
    MessageReactionEntry entry,
  ) async {
    final details = await MatrixService().client.getRoomDetails(
      roomId: widget.roomId,
    );
    if (!context.mounted) return;
    final theme = Theme.of(context);
    final ownId = details.currentUserId.trim().isNotEmpty
        ? details.currentUserId
        : null;
    final mq = MediaQuery.sizeOf(context);
    await showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        mq.width * 0.35,
        mq.height * 0.25,
        mq.width * 0.35,
        mq.height * 0.25,
      ),
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.45),
        ),
      ),
      color: MatrixTheme.terminalBackground,
      items: [
        PopupMenuItem<void>(
          enabled: false,
          child: Text(
            '${entry.key}  ·  ${entry.count}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ...entry.senders.map((u) {
          final isSelf = ownId != null && u == ownId;
          return PopupMenuItem<void>(
            onTap: isSelf
                ? () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      unawaited(toggleTimelineReaction(message, entry.key));
                    });
                  }
                : null,
            child: ListTile(
              dense: true,
              leading: Icon(
                Icons.person_outline,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              title: Text(u, overflow: TextOverflow.ellipsis),
              trailing: isSelf
                  ? Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: theme.colorScheme.error,
                    )
                  : null,
            ),
          );
        }),
      ],
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
      final usePollDialog = isDesktopTargetPlatform();

      Widget pollShell(BuildContext shellCtx, {required bool desktopChrome}) {
        return StatefulBuilder(
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
            final maxSelItems = List.generate(nAnswers, (i) => i + 1);

            return DecoratedBox(
              decoration: BoxDecoration(
                color: MatrixTheme.terminalBlack.withValues(alpha: 0.98),
                borderRadius: desktopChrome
                    ? BorderRadius.circular(12)
                    : const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border.all(
                  color: MatrixTheme.matrixGreen.withValues(alpha: 0.4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: MatrixTheme.matrixAccent.withValues(alpha: 0.12),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!desktopChrome) ...[
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
                  ],
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
                            color: MatrixTheme.matrixDarkGreen.withValues(
                              alpha: 0.9,
                            ),
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
                                color: MatrixTheme.matrixGreen.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide(
                                color: MatrixTheme.matrixGreen.withValues(
                                  alpha: 0.35,
                                ),
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
                                color: MatrixTheme.matrixDarkGreen.withValues(
                                  alpha: 0.9,
                                ),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: answerCtrls[i],
                                    style: TextStyle(
                                      color: MatrixTheme.matrixLightGreen,
                                      fontFamily: MatrixTheme.fontFamily,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: 'Option ${i + 1}',
                                      labelStyle: TextStyle(
                                        color: MatrixTheme.matrixGreen
                                            .withValues(alpha: 0.7),
                                        fontFamily: MatrixTheme.fontFamily,
                                        fontSize: 12,
                                      ),
                                      filled: true,
                                      fillColor: MatrixTheme.terminalBackground
                                          .withValues(alpha: 0.85),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(4),
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
                            color: MatrixTheme.matrixDarkGreen.withValues(
                              alpha: 0.9,
                            ),
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
                              color: MatrixTheme.matrixGreen.withValues(
                                alpha: 0.35,
                              ),
                            ),
                            color: MatrixTheme.terminalBackground.withValues(
                              alpha: 0.75,
                            ),
                          ),
                          child: Column(
                            children: [
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => setSt(() => disclosed = false),
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
                                          ? MatrixTheme.matrixAccent.withValues(
                                              alpha: 0.08,
                                            )
                                          : null,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Undisclosed',
                                          style: TextStyle(
                                            color: MatrixTheme.matrixLightGreen,
                                            fontFamily: MatrixTheme.fontFamily,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Counts stay hidden until the poll is closed.',
                                          style: TextStyle(
                                            color: MatrixTheme.matrixDarkGreen
                                                .withValues(alpha: 0.95),
                                            fontFamily: MatrixTheme.fontFamily,
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
                                color: MatrixTheme.matrixGreen.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => setSt(() => disclosed = true),
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
                                          ? MatrixTheme.matrixAccent.withValues(
                                              alpha: 0.08,
                                            )
                                          : null,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Disclosed',
                                          style: TextStyle(
                                            color: MatrixTheme.matrixLightGreen,
                                            fontFamily: MatrixTheme.fontFamily,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Show who voted for each option as votes arrive.',
                                          style: TextStyle(
                                            color: MatrixTheme.matrixDarkGreen
                                                .withValues(alpha: 0.95),
                                            fontFamily: MatrixTheme.fontFamily,
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
                              dropdownColor: MatrixTheme.terminalBlack,
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
                              onChanged: (v) => setSt(() => maxSel = v ?? 1),
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
                                  foregroundColor: MatrixTheme.matrixGreen,
                                  side: BorderSide(
                                    color: MatrixTheme.matrixGreen.withValues(
                                      alpha: 0.5,
                                    ),
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
                                  backgroundColor: MatrixTheme.matrixAccent,
                                  foregroundColor: MatrixTheme.terminalBlack,
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
        );
      }

      if (usePollDialog) {
        await showGeneralDialog<void>(
          context: context,
          barrierDismissible: true,
          barrierLabel: MaterialLocalizations.of(
            context,
          ).modalBarrierDismissLabel,
          transitionDuration: const Duration(milliseconds: 200),
          transitionBuilder: (dialogCtx, animation, _, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
                child: child,
              ),
            );
          },
          pageBuilder: (dialogCtx, a1, a2) {
            final mq = MediaQuery.sizeOf(dialogCtx);
            return Center(
              child: Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                elevation: 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 560,
                    maxHeight: mq.height * 0.9,
                  ),
                  child: SizedBox(
                    width: 520,
                    height: mq.height * 0.82,
                    child: DesktopEscScope(
                      child: pollShell(dialogCtx, desktopChrome: true),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      } else {
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
                  child: pollShell(ctx, desktopChrome: false),
                ),
              ),
            );
          },
        );
      }
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
        (_) => ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Poll sent'))),
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

  Future<void> voteOnPoll(String pollEventId, List<String> answerIds) async {
    if (pollEventId.isEmpty || answerIds.isEmpty) return;
    final r = await model.sendPollResponse(
      roomId: widget.roomId,
      pollStartEventId: pollEventId,
      answerIds: answerIds,
    );
    if (!context.mounted) return;
    r.fold(
      (_) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vote recorded'))),
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
    final choice = await showAdaptiveSheet<String>(
      context: context,
      title: 'Attach',
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isDesktopTargetPlatform())
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
                  Icons.photo_camera_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Camera'),
                subtitle: Text(
                  isDesktopTargetPlatform()
                      ? 'Webcam (pick device if several are available)'
                      : 'Photo or video',
                ),
                onTap: () => Navigator.pop(sheetContext, 'camera'),
              ),
              ListTile(
                leading: Icon(
                  Icons.mic_none_rounded,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Voice message'),
                subtitle: const Text('Record and send'),
                onTap: () => Navigator.pop(sheetContext, 'voice'),
              ),
              ListTile(
                leading: Icon(
                  Icons.folder_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('File'),
                subtitle: Text(
                  isDesktopTargetPlatform()
                      ? 'Images, video, documents'
                      : 'Browse files',
                ),
                onTap: () => Navigator.pop(sheetContext, 'file'),
              ),
            ],
          ),
        );
      },
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'gallery') {
      if (!isDesktopTargetPlatform()) {
        await pickAndSendFromGallery();
      }
    } else if (choice == 'camera') {
      await showCameraCaptureMenu();
    } else if (choice == 'voice') {
      await showVoiceRecordSheet();
    } else if (choice == 'file') {
      await pickAndSendFile();
    }
  }

  /// Photo vs video from the device camera (not supported on web).
  Future<void> showCameraCaptureMenu() async {
    if (kIsWeb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera is not supported on web.')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final theme = Theme.of(context);
    final mode = await showAdaptiveSheet<String>(
      context: context,
      title: 'Camera',
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.photo_camera_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Photo'),
                subtitle: const Text('Take a picture'),
                onTap: () => Navigator.pop(sheetContext, 'photo'),
              ),
              ListTile(
                leading: Icon(
                  Icons.videocam_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Video'),
                subtitle: const Text('Record a clip'),
                onTap: () => Navigator.pop(sheetContext, 'video'),
              ),
              if (isDesktopTargetPlatform()) ...[
                ListTile(
                  leading: Icon(
                    Icons.folder_open_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('Choose image or video file'),
                  subtitle: const Text('When camera is unavailable'),
                  onTap: () => Navigator.pop(sheetContext, 'filemedia'),
                ),
              ],
            ],
          ),
        );
      },
    );
    if (mode == null || !context.mounted) return;
    if (mode == 'photo') {
      await pickAndSendFromCameraPhoto();
    } else if (mode == 'video') {
      await pickAndSendFromCameraVideo();
    } else if (mode == 'filemedia') {
      await pickAndSendMediaFromFilePicker();
    }
  }

  Future<void> pickAndSendFromCameraPhoto() async {
    if (kIsWeb) return;
    if (isDesktopTargetPlatform()) {
      final cam = await pickDesktopCameraDescription(context);
      if (!context.mounted) return;
      if (cam == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No camera found. Attach an image with File instead.',
            ),
          ),
        );
        return;
      }
      final path = await showDialog<String?>(
        context: context,
        builder: (_) => DesktopCameraCaptureDialog(camera: cam),
      );
      if (path == null || path.isEmpty || !context.mounted) return;
      await _sendTimelineFileFromPath(path, mimeType: 'image/jpeg');
      return;
    }
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (picked == null) return;
      final path = await _pathForGalleryPick(picked);
      if (path == null || path.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access the camera photo.')),
          );
        }
        return;
      }
      await _sendTimelineFileFromPath(
        path,
        mimeType: picked.mimeType ?? 'image/jpeg',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Camera unavailable: $e. Try “Choose image or video file”.',
            ),
          ),
        );
      }
    }
  }

  Future<void> pickAndSendFromCameraVideo() async {
    if (kIsWeb) return;
    if (isDesktopTargetPlatform()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Recording video from the camera is not available on desktop. '
              'Choose a video file from File or “Choose image or video file”.',
            ),
          ),
        );
      }
      await pickAndSendMediaFromFilePicker();
      return;
    }
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 10),
      );
      if (picked == null) return;
      final path = await _pathForGalleryPick(picked);
      if (path == null || path.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access the camera video.')),
          );
        }
        return;
      }
      await _sendTimelineFileFromPath(
        path,
        mimeType: picked.mimeType ?? 'video/mp4',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Camera unavailable: $e. Try “Choose image or video file”.',
            ),
          ),
        );
      }
    }
  }

  Future<void> showVoiceRecordSheet() async {
    if (kIsWeb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice messages are not supported on web.'),
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final result = await showAdaptivePanel<VoiceRecordResult?>(
      context: context,
      scrollControlled: true,
      builder: (ctx) => const VoiceRecordSheet(),
    );
    if (result == null || result.path.isEmpty || !context.mounted) return;
    await _sendTimelineFileFromPath(
      result.path,
      mimeType: 'audio/mp4',
      audioDurationMs: result.durationMs,
      audioWaveformNormalized: result.waveform,
      audioAsVoiceMessage: true,
    );
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
    if (isDesktopTargetPlatform()) {
      await pickAndSendMediaFromFilePicker();
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

  /// Desktop / fallback: images & videos via file picker (ImagePicker gallery is unreliable).
  Future<void> pickAndSendMediaFromFilePicker() async {
    if (kIsWeb) return;
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'heic',
        'bmp',
        'mp4',
        'mov',
        'webm',
        'mkv',
        'avi',
        'm4v',
      ],
      allowMultiple: false,
      withData: kIsWeb || !isDesktopTargetPlatform(),
      lockParentWindow: isDesktopTargetPlatform(),
    );
    if (pick == null || pick.files.isEmpty) return;
    if (!context.mounted) return;
    final platformFile = pick.files.single;
    final path = await _pathForFilePick(platformFile);
    if (path == null || path.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read the selected image or video.'),
          ),
        );
      }
      return;
    }
    final mime = _mimeForPickedFile(platformFile, path);
    await _sendTimelineFileFromPath(path, mimeType: mime);
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
      case '.m4a':
        return 'audio/mp4';
      case '.aac':
        return 'audio/aac';
      case '.mp3':
        return 'audio/mpeg';
      case '.ogg':
        return 'audio/ogg';
      case '.opus':
        return 'audio/opus';
      case '.wav':
        return 'audio/wav';
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
    return _mimeByDottedExtension(
      path_lib.extension(resolvedPath).toLowerCase(),
    );
  }

  Future<void> pickAndSendFile() async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: kIsWeb || !isDesktopTargetPlatform(),
      lockParentWindow: isDesktopTargetPlatform(),
    );
    if (pick == null || pick.files.isEmpty) return;
    if (!context.mounted) return;
    final platformFile = pick.files.single;
    final path = await _pathForFilePick(platformFile);
    if (path == null || path.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the selected file.')),
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
    int? audioDurationMs,
    List<double>? audioWaveformNormalized,
    bool audioAsVoiceMessage = false,
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
            audioDurationMs: audioDurationMs,
            audioWaveformNormalized: audioWaveformNormalized,
            audioAsVoiceMessage: audioAsVoiceMessage,
            sendAttachment:
                ({
                  prep,
                  required originalFilePath,
                  required onProgress,
                  int? audioDurationMs,
                  List<double>? audioWaveformNormalized,
                  required bool audioAsVoiceMessage,
                }) => model.sendTimelineAttachment(
                  roomId: widget.roomId,
                  originalFilePath: originalFilePath,
                  prep: prep,
                  caption: caption.isEmpty ? null : caption,
                  audioDurationMs: audioDurationMs,
                  audioWaveformNormalized: audioWaveformNormalized,
                  audioAsVoiceMessage: audioAsVoiceMessage,
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
        audioDurationMs: audioDurationMs,
        audioWaveformNormalized: audioWaveformNormalized,
        audioAsVoiceMessage: audioAsVoiceMessage,
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
    final page = RoomInfoScreen(
      roomId: widget.roomId,
      initialTitle: widget.roomName,
    );
    final launcher = DesktopShellScope.maybeOf(context);
    final RoomInfoNavResult? result;
    if (launcher != null && isDesktopTargetPlatform()) {
      result = await launcher.openShellFlow<RoomInfoNavResult?>(
        anchorContext: context,
        page: page,
        windowTitle: 'Room info',
        preferredWindowSize: const Size(580, 760),
      );
    } else {
      result = await Navigator.of(
        context,
      ).push<RoomInfoNavResult?>(MaterialPageRoute(builder: (ctx) => page));
    }
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

  String _effectiveSenderAvatarMxcForSheet(Message message) {
    final uid = message.senderUserId.trim();
    if (uid.isNotEmpty) {
      final live = senderAvatarMxcByUserId.value[uid]?.trim() ?? '';
      if (live.isNotEmpty) return live;
    }
    final t = message.senderAvatarMxc.trim();
    if (t.isNotEmpty) return t;
    if (message.isOwn) {
      final o = ProfilePrefs.instance.ownAvatarMxc?.trim() ?? '';
      if (o.isNotEmpty) return o;
    }
    return '';
  }

  Future<void> onSenderAvatarTap(BuildContext anchorContext, Message message) {
    final uid = message.senderUserId.trim();
    if (uid.isEmpty) return Future.value();
    if (!anchorContext.mounted) return Future.value();
    final title = message.sender.trim().isNotEmpty ? message.sender.trim() : uid;
    return _presentSenderProfileSheet(
      anchorContext,
      message: message,
      displayTitle: title,
      showDirectMessageAction: !message.isOwn,
    );
  }

  Future<void> _presentSenderProfileSheet(
    BuildContext anchorContext, {
    required Message message,
    required String displayTitle,
    required bool showDirectMessageAction,
  }) async {
    if (!anchorContext.mounted) return;
    final theme = Theme.of(anchorContext);
    final scheme = theme.colorScheme;
    final uid = message.senderUserId.trim();
    final mxc = _effectiveSenderAvatarMxcForSheet(message);
    const avatarSize = 56.0;

    Widget body(BuildContext sheetCtx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: MatrixTheme.terminalBorder.withValues(alpha: 0.9),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: mxc.isEmpty
                    ? ColoredBox(
                        color: scheme.primary.withValues(alpha: 0.12),
                        child: Center(
                          child: Text(
                            () {
                              final d = displayTitle.trim();
                              if (d.isEmpty) return '?';
                              return d.substring(0, 1).toUpperCase();
                            }(),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      )
                    : FutureBuilder<Uint8List?>(
                        future: fetchUserAvatarThumbnail(mxc),
                        builder: (context, snap) {
                          if (snap.hasData &&
                              snap.data != null &&
                              snap.data!.isNotEmpty) {
                            return Image.memory(
                              snap.data!,
                              fit: BoxFit.cover,
                              width: avatarSize,
                              height: avatarSize,
                              gaplessPlayback: true,
                            );
                          }
                          return Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.primary,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              displayTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFamily: MatrixTheme.fontFamily,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            SelectableText(
              uid,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFamily: MatrixTheme.fontFamily,
              ),
              textAlign: TextAlign.center,
            ),
            if (showDirectMessageAction) ...[
              const SizedBox(height: 20),
              TerminalButton(
                text: 'MESSAGE',
                icon: Icons.chat_bubble_outline,
                onPressed: () async {
                  Navigator.of(sheetCtx).pop();
                  await _openOrFocusDirectChat(
                    otherUserId: uid,
                    roomTitle: displayTitle,
                  );
                },
              ),
            ],
          ],
        ),
      );
    }

    if (isDesktopTargetPlatform() && preferDialogOverModalSheet(anchorContext)) {
      await showDialog<void>(
        context: anchorContext,
        builder: (dialogCtx) {
          return AlertDialog(
            backgroundColor: MatrixTheme.terminalBackground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: MatrixTheme.terminalBorder),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: body(dialogCtx),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: Text(
                  'Close',
                  style: TextStyle(
                    fontFamily: MatrixTheme.fontFamily,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          );
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: anchorContext,
      showDragHandle: true,
      backgroundColor: MatrixTheme.terminalBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        side: BorderSide(color: MatrixTheme.terminalBorder),
      ),
      builder: body,
    );
  }

  Future<void> _openOrFocusDirectChat({
    required String otherUserId,
    required String roomTitle,
  }) async {
    if (!context.mounted || _disposed) return;
    final client = MatrixService().client;
    String? roomId;
    try {
      roomId = await client.getExistingDmRoomId(userId: otherUserId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not look up direct chat: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }
    if (!context.mounted || _disposed) return;
    if (roomId == null || roomId.isEmpty) {
      try {
        roomId = await client.createDirectRoom(userId: otherUserId);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not start direct chat: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
    }
    if (!context.mounted || _disposed) return;
    if (roomId == widget.roomId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are already in this direct chat.')),
      );
      return;
    }
    final page = ConversationScreen(
      roomId: roomId,
      roomName: roomTitle,
      status: ChatRoomStatus.joined,
    );
    final launcher = DesktopShellScope.maybeOf(context);
    if (launcher != null && isDesktopTargetPlatform()) {
      await launcher.openShellFlow<void>(
        anchorContext: context,
        page: page,
        windowTitle: roomTitle,
        preferredWindowSize: const Size(520, 720),
      );
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (ctx) => page),
      );
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

  static bool _timelineMsNear(BigInt a, BigInt b, int maxDeltaMs) {
    return (a.toInt() - b.toInt()).abs() <= maxDeltaMs;
  }

  /// Shorter snapshot whose tail no longer matches [previous] can drop the local echo *before*
  /// the remote row is applied — the bubble flickers off then on. Skip those until the next diff.
  ///
  /// Mirrors the “delivered twin” idea in Rust [dedupe_stale_local_echoes].
  static bool _timelineSnapshotDropsInFlightOwn(
    List<Message> incoming,
    List<Message> previous,
  ) {
    if (previous.isEmpty || incoming.isEmpty) return false;
    if (incoming.length >= previous.length) return false;

    bool hasIdentity(Message m, List<Message> list) {
      for (final o in list) {
        if (m.eventId.isNotEmpty && m.eventId == o.eventId) return true;
        if (m.transactionId.isNotEmpty && m.transactionId == o.transactionId) {
          return true;
        }
      }
      return false;
    }

    bool hasDeliveredTwin(Message pending, List<Message> list) {
      for (final o in list) {
        if (!o.isOwn || o.sendState != EventSendStateKind.delivered) continue;
        if (o.messageType != MessageType.message) continue;
        if (o.content != pending.content) continue;
        if (o.inReplyToEventId != pending.inReplyToEventId) continue;
        if (o.roomMsgKind != pending.roomMsgKind) continue;
        if (!_timelineMsNear(pending.timestamp, o.timestamp, 300000)) continue;
        return true;
      }
      return false;
    }

    for (final m in previous) {
      if (m.messageType != MessageType.message) continue;
      if (!m.isOwn) continue;
      if (m.sendState != EventSendStateKind.pending &&
          m.sendState != EventSendStateKind.failed) {
        continue;
      }
      if (hasIdentity(m, incoming)) continue;
      if (hasDeliveredTwin(m, incoming)) continue;
      return true;
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
              if (_timelineSnapshotDropsInFlightOwn(list, prev.messages)) {
                LoggingService.info(
                  'CONVERSATION_SCREEN',
                  'Ignoring timeline snapshot that drops in-flight own message '
                  '(${list.length} < ${prev.messages.length})',
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
            if (widget.status == ChatRoomStatus.joined) {
              _scheduleMarkTimelineRead();
            }
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
