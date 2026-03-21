import 'dart:async';
import 'dart:io';

import 'package:elementary/elementary.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';

import 'package:matrix/src/core/state_management/base_state_widget_model.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/features/conversation/domain/models/conversation_state.dart'
    hide MessageType;
import 'package:matrix/src/features/conversation/domain/services/conversation_service.dart';
import 'package:matrix/src/core/video_send_media_prep.dart';
import 'package:matrix/src/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:matrix/src/features/conversation/presentation/screens/media_outgoing_send_screen.dart';
import 'package:matrix/src/features/conversation/presentation/screens/room_info_screen.dart';
import 'package:matrix/src/features/conversation/presentation/widgets/attachment_viewer.dart';
import 'package:matrix_sdk/matrix_sdk.dart'
    show FileSendPhase, FileSendProgress, Message, MessageType;
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:result_dart/result_dart.dart';

class ConversationScreenModel extends ElementaryModel {
  ConversationScreenModel(this.conversationService) : super();
  final ConversationService conversationService;

  Future<Result<List<Message>>> loadMessages(String roomId) async {
    final messages = await conversationService.loadMessages(roomId);
    return messages;
  }

  Future<ConversationInfo> loadRoomInfo() async {
    final roomInfo = await conversationService.loadRoomInfo();
    return roomInfo;
  }

  Future<Result<String>> sendMessage(String roomId, String content) async {
    return conversationService.sendMessage(roomId, content);
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
}

class ConversationScreenWM
    extends BaseWidgetModel<ConversationScreen, ConversationScreenModel> {
  ConversationScreenWM(super.model);
  late final ValueNotifier<ConversationState> _roomState;
  late final ValueNotifier<bool> _isInvited;
  late final TextEditingController _messageController;

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

  // Stream management: full message list from Rust
  StreamSubscription<List<Message>>? _timelineListSubscription;
  ConversationInfo? _roomInfo;
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
    _fileSendProgress.dispose();
    jumpToTimelineEventId.dispose();
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
      _roomInfo = await model.loadRoomInfo();
    } catch (_) {
      _roomInfo = ConversationInfo(
        id: widget.roomId,
        name: widget.roomName,
        topic: '',
        memberCount: 0,
      );
    }
    _listenToChatUpdates();
  }

  Future<void> sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    try {
      final result = await model.sendMessage(widget.roomId, content);
      result.fold((eventId) {
        _messageController.clear();
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
              roomInfo: roomInfo,
            );
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
