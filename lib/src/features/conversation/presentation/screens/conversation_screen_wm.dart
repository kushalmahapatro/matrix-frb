import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:matrix/src/core/state_management/base_state_widget_model.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/features/conversation/domain/models/conversation_state.dart'
    hide MessageType;
import 'package:matrix/src/features/conversation/domain/services/conversation_service.dart';
import 'package:matrix/src/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:matrix/src/rust/matrix/timelines.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
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
    final result = await conversationService.sendMessage(roomId, content);
    return result;
  }

  Stream<MessageUpdate> subscribeToChatUpdates(String roomId) {
    return conversationService.subscribeToTimelineUpdates(roomId);
  }

  Future<Result<String>> acceptInvite(String roomId) {
    return conversationService.acceptInvite(roomId);
  }

  Future<Result<String>> rejectInvite(String roomId) {
    return conversationService.rejectInvite(roomId);
  }

  Future<Result<List<Message>>> fetchOlderMessages({
    required String conversationId,
    int count = 20,
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

  // Stream management
  StreamSubscription<MessageUpdate>? _chatUpdatesSubscription;
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
  void dispose() {
    _disposeStreams();
    _roomState.dispose();
    _messageController.dispose();
    _isInvited.dispose();
    _disposed = true;
    super.dispose();
  }

  void _disposeStreams() {
    _chatUpdatesSubscription?.cancel();
    _chatUpdatesSubscription = null;
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    _isStreamActive = false;
  }

  Future<void> _loadMessages() async {
    _roomState.value = const ConversationState.loading();

    try {
      final messages = await model.loadMessages(widget.roomId);
      final roomInfo = await model.loadRoomInfo();

      messages.fold(
        (success) =>
            _roomState.value = ConversationState.loaded(
              messages: success.toList(),
              roomInfo: roomInfo,
            ),
        (failure) =>
            _roomState.value = ConversationState.error(
              message: 'Failed to load messages: $failure',
            ),
      );
    } catch (e) {
      _roomState.value = ConversationState.error(
        message: 'Failed to load messages: $e',
      );
    }
    _listenToChatUpdates();
  }

  Future<void> sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    try {
      final success = await model.sendMessage(widget.roomId, content);
      if (success.isSuccess()) {
        _messageController.clear();
      }
    } catch (e) {
      // Show error message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: MatrixTheme.errorRed,
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
    print('Starting chat updates subscription for room: ${widget.roomId}');
    _disposeStreams(); // Clean up any existing streams

    _chatUpdatesSubscription = model
        .subscribeToChatUpdates(widget.roomId)
        .listen(
          (update) {
            _lastUpdateTime = DateTime.now();
            _isStreamActive = true;

            print('Received update: ${update.messageUpdateType}');

            final currentState = roomState.value;
            if (currentState is! RoomStateLoaded) {
              return;
            }

            List<Message> newMessages = [];
            switch (update.messageUpdateType) {
              case MessageUpdateType.append:
                if (update.messages != null) {
                  newMessages = [
                    ...currentState.messages,
                    ...update.messages ?? [],
                  ];
                }
                break;
              case MessageUpdateType.pushFront:
                if (update.messages != null && update.messages!.length == 1) {
                  newMessages = [
                    ...update.messages ?? [],
                    ...currentState.messages,
                  ];
                }
                break;
              case MessageUpdateType.remove:
                if (update.index != null &&
                    update.index!.toInt() < currentState.messages.length &&
                    update.index!.toInt() >= 0) {
                  newMessages = List<Message>.from(currentState.messages);
                  newMessages.removeAt(update.index!.toInt());
                }
                break;
              case MessageUpdateType.reset:
                if (update.messages != null) {
                  newMessages = update.messages ?? [];
                }
                break;
              case MessageUpdateType.truncate:
                if (update.index != null &&
                    update.index!.toInt() < currentState.messages.length &&
                    update.index!.toInt() >= 0) {
                  newMessages = List<Message>.from(currentState.messages);
                  newMessages.removeRange(
                    update.index!.toInt(),
                    newMessages.length,
                  );
                }
                break;
              case MessageUpdateType.set_:
                if (update.index != null &&
                    update.messages != null &&
                    update.messages!.length == 1 &&
                    update.index!.toInt() < currentState.messages.length &&
                    update.index!.toInt() >= 0) {
                  newMessages = List<Message>.from(currentState.messages);
                  newMessages[update.index!.toInt()] = update.messages!.first;
                }
                break;
              case MessageUpdateType.insert:
                if (update.index != null &&
                    update.messages != null &&
                    update.messages!.length == 1 &&
                    update.index!.toInt() < currentState.messages.length &&
                    update.index!.toInt() >= 0) {
                  newMessages = List<Message>.from(currentState.messages);
                  newMessages.insert(
                    update.index!.toInt(),
                    update.messages!.first,
                  );
                }
                break;
              case MessageUpdateType.popBack:
                if (update.index != null &&
                    update.messages != null &&
                    update.messages!.length == 1) {
                  newMessages = List<Message>.from(currentState.messages);
                  newMessages.removeLast();
                }
                break;
              case MessageUpdateType.popFront:
                if (update.messages != null && update.messages!.length == 1) {
                  newMessages = List<Message>.from(currentState.messages);
                  newMessages.removeAt(0);
                }
                break;
              case MessageUpdateType.pushBack:
                if (update.messages != null && update.messages!.length == 1) {
                  newMessages = List<Message>.from(currentState.messages);
                  newMessages.add(update.messages!.first);
                }
                break;
              case MessageUpdateType.clear:
                if (update.messages != null && update.messages!.length == 1) {
                  newMessages = List<Message>.from(currentState.messages);
                  newMessages.clear();
                }
                break;
              case MessageUpdateType.readMarker:
                // Heartbeat message - just update timestamp, don't change UI
                print('Received heartbeat, updating last update time');
                _lastUpdateTime = DateTime.now();
                return;
              case MessageUpdateType.timelineStart:
                // Initial connection message - just update timestamp, don't change UI
                print('Timeline subscription started successfully');
                _lastUpdateTime = DateTime.now();
                return;
            }

            if (!_disposed && newMessages.isNotEmpty) {
              print('Updating messages, new count: ${newMessages.length}');
              _roomState.value = currentState.copyWith(messages: newMessages);
            }
          },
          onError: (error) {
            print('Chat updates stream error: $error');
            _isStreamActive = false;
            _scheduleReconnection();
          },
          onDone: () {
            print('Chat updates stream completed');
            _isStreamActive = false;
            _scheduleReconnection();
          },
        );

    // Start health check timer
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
      print(
        'Health check: Stream active: $_isStreamActive, Time since last update: ${timeSinceLastUpdate.inSeconds}s',
      );

      if (timeSinceLastUpdate > _maxInactivityTime) {
        print(
          'Chat updates stream inactive for too long (${timeSinceLastUpdate.inMinutes} minutes), reconnecting...',
        );
        _isStreamActive = false;
        _scheduleReconnection();
      }
    });
  }

  void _scheduleReconnection() {
    if (_disposed || _reconnectionTimer != null) return;

    print(
      'Scheduling reconnection in ${_reconnectionDelay.inSeconds} seconds...',
    );
    _reconnectionTimer = Timer(_reconnectionDelay, () {
      if (_disposed) return;

      print('Attempting to reconnect chat updates stream...');
      _listenToChatUpdates();
    });
  }

  void _forceReconnect() {
    if (_disposed) return;

    print('Force reconnecting chat updates stream...');
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

  Future<List<Message>> fetchOlderMessages({
    required String conversationId,
    int limit = 20,
  }) async {
    final result = await model.fetchOlderMessages(
      conversationId: conversationId,
      count: limit,
    );

    return result.fold((success) => success, (failure) => []);
  }
}
