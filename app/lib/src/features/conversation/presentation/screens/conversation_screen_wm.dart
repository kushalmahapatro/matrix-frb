import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'dart:async';

import 'package:matrix/src/core/state_management/base_state_widget_model.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/features/conversation/domain/models/conversation_state.dart'
    hide MessageType;
import 'package:matrix/src/features/conversation/domain/services/conversation_service.dart';
import 'package:matrix/src/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:matrix_sdk/matrix_sdk.dart';
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

  /// Full message list from Rust on every change (no delta merge in Dart).
  Stream<List<Message>> subscribeToTimelineList(String roomId) {
    return conversationService.subscribeToTimelineList(roomId);
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

  // Stream status getters
  bool get isStreamActive => _isStreamActive;
  bool get isReconnecting => _reconnectionTimer != null;

  bool _disposed = false;

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

  void showRoomInfo() {
    widget.showRoomInfo(context);
  }

  void retry() {
    _loadMessages();
  }

  void _listenToChatUpdates() {
    LoggingService.info(
      'CONVERSATION_SCREEN',
      'Starting timeline list subscription for room: ${widget.roomId}',
    );
    _disposeStreams();
    MatrixService().cancelTimelineSubscriptionForRoom(widget.roomId);

    final roomInfo = _roomInfo ?? ConversationInfo(
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

    MatrixService().registerTimelineSubscription(widget.roomId, _timelineListSubscription!);
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

    return result.fold(
      (fullList) {
        final previousLength = currentState.messages.length;
        _roomState.value = currentState.copyWith(messages: fullList);
        final hasMore = fullList.length > previousLength;
        return (List<Message>.from([]), hasMore);
      },
      (failure) => (List<Message>.from([]), false),
    );
  }
}
