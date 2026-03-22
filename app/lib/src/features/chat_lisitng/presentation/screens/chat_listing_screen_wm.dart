import 'dart:async';
import 'dart:typed_data';

import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix/src/core/timeline_local_hidden_store.dart';
import 'package:matrix/src/core/state_management/base_state_widget_model.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/features/chat_lisitng/presentation/screens/chat_listing_screen.dart';
import 'package:matrix_sdk/matrix_sdk.dart' show Message, RoomUpdate;
import 'package:result_dart/result_dart.dart';

String _roomListLastMessageLine(Message? message) {
  if (message == null) return '';
  if (message.isRedacted) return 'Message deleted';
  if (TimelineLocalHiddenStore.isHidden(message)) {
    return 'Message removed on this device';
  }
  return message.content;
}

class ChatListingScreenModel extends ElementaryModel {
  ChatListingScreenModel(this._matrixService) : super();
  final MatrixService _matrixService;

  /// Server-generated thumbnail bytes for the room list (see [Chat.lastPreview]).
  Future<Uint8List?> loadListingThumbnail(String roomId, Message message) async {
    if (message.isRedacted) return null;
    if (TimelineLocalHiddenStore.isHidden(message)) return null;
    final id = message.eventId.isNotEmpty
        ? message.eventId
        : message.transactionId;
    if (id.isEmpty) return null;
    try {
      return await _matrixService.client.fetchRoomMessageMedia(
        roomId: roomId,
        eventId: id,
        thumbnail: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<Chat>> loadRooms() async {
    Result<List<RoomUpdate>> result;
    try {
      final response = await _matrixService.client.getAllRooms();
      result = Success(response);
    } catch (e) {
      result = Failure(Exception(e));
    }
    return result.fold(
      (success) => success
          .map(
            (room) => Chat(
              id: room.roomId,
              name: room.displayName ?? room.rawName ?? '',
              lastMessage: _roomListLastMessageLine(room.message),
              lastActivity:
                  (room.message?.timestamp ?? BigInt.from(0)) > BigInt.from(0)
                  ? DateTime.fromMillisecondsSinceEpoch(
                      room.message!.timestamp.toInt(),
                    )
                  : null,
              isDirect: room.isDm ?? false,
              unreadCount: room.unreadMessages?.toInt() ?? 0,
              status: ChatRoomStatus.values.firstWhere(
                (status) => status.name == room.updateType.name,
              ),
              lastPreview: room.message,
            ),
          )
          .toList(),
      (failure) {
        LoggingService.error(
          'CHAT_LISTING_SCREEN',
          'Failed to load rooms: $failure',
        );
        return [];
      },
    );
  }

  /// Canonical room list from Rust (full list on every change; no merge in Dart).
  Stream<List<Chat>> subscribeToRoomList() {
    return _matrixService.client.subscribeToRoomList().map(_roomUpdatesToChatList);
  }

  static List<Chat> _roomUpdatesToChatList(List<RoomUpdate> updates) {
    return updates.map(_roomUpdateToChat).toList();
  }

  static Chat _roomUpdateToChat(RoomUpdate roomUpdate) {
    return Chat(
      id: roomUpdate.roomId,
      name: roomUpdate.displayName ?? roomUpdate.rawName ?? '',
      lastMessage: _roomListLastMessageLine(roomUpdate.message),
      lastActivity:
          (roomUpdate.message?.timestamp ?? BigInt.from(0)) > BigInt.from(0)
              ? DateTime.fromMillisecondsSinceEpoch(
                  roomUpdate.message!.timestamp.toInt(),
                )
              : null,
      isDirect: roomUpdate.isDm ?? false,
      unreadCount: roomUpdate.unreadMessages?.toInt() ?? 0,
      status: ChatRoomStatus.values.firstWhere(
        (status) => status.name == roomUpdate.updateType.name,
      ),
      lastPreview: roomUpdate.message,
    );
  }
}

class ChatListingScreenWM
    extends BaseWidgetModel<ChatListingScreen, ChatListingScreenModel> {
  ChatListingScreenWM(super.model);
  final ValueNotifier<ChatState> _chatState = ValueNotifier(
    const ChatState.loading(),
  );

  ValueNotifier<ChatState> get chatState => _chatState;
  final ValueNotifier<ChatType> _selectedChatType = ValueNotifier(ChatType.all);

  ValueNotifier<ChatType> get selectedChatType => _selectedChatType;

  // Stream subscription: full room list from Rust on every change
  StreamSubscription<List<Chat>>? _roomListSubscription;
  bool _isSubscribed = false;
  Timer? _reconnectionTimer;
  Timer? _healthCheckTimer;
  int _reconnectionAttempts = 0;
  DateTime? _lastUpdateTime;
  static const int _maxReconnectionAttempts = 10;
  static const Duration _initialReconnectionDelay = Duration(seconds: 1);
  static const Duration _maxReconnectionDelay = Duration(seconds: 30);
  static const Duration _healthCheckInterval = Duration(seconds: 30);

  /// While sync starts, the room list stream can emit `[]` before rooms arrive.
  /// Keep the loading UI briefly instead of flashing "no rooms".
  Timer? _emptyRoomListSettleTimer;
  static const Duration _emptyListSettleDuration = Duration(milliseconds: 1200);

  @override
  void initWidgetModel() {
    super.initWidgetModel();

    unawaited(TimelineLocalHiddenStore.ensureLoaded());
    _loadAllChats();
    _listenToChatUpdates();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && _isSubscribed) {
      LoggingService.info(
        'CHAT_LISTING_SCREEN',
        'App resumed, restarting sync to restore room updates',
      );
      _restartSyncAndResubscribe();
    }
  }

  @override
  void dispose() {
    _emptyRoomListSettleTimer?.cancel();
    _isSubscribed = false;
    MatrixService().unregisterRoomUpdatesSubscription();
    _roomListSubscription?.cancel();
    _roomListSubscription = null;
    _reconnectionTimer?.cancel();
    _stopHealthCheck();
    _chatState.dispose();
    super.dispose();
  }

  Future<void> _loadAllChats() async {
    _chatState.value = const ChatState.loading();
    _listenToChatUpdates();
  }

  Future<void> createRoom() async {
    final result = await widget.navigateToCreateScreen(context);
    if (result != null) {
      await Future.delayed(const Duration(seconds: 2));
      ChatState currentState = _chatState.value;
      if (currentState is ChatStateLoaded) {
        final room = currentState.rooms.firstWhere(
          (element) => element.id == result,
          orElse: () => Chat(
            id: '',
            name: '',
            lastMessage: '',
            status: ChatRoomStatus.invited,
          ),
        );

        if (room.id.isNotEmpty && context.mounted) {
          widget.navigateToConversationScreen(
            context,
            room.id,
            room.name,
            room.status,
          );
        }
      }
    }
  }

  void openSettings() {
    widget.navigateToSettingsScreen(context);
  }

  void _onRoomList(List<Chat> list) {
    LoggingService.info(
      'CHAT_LISTING_SCREEN',
      'Received room list: ${list.length} rooms',
    );
    _emptyRoomListSettleTimer?.cancel();

    if (list.isEmpty) {
      final hadRooms = _chatState.value.maybeWhen(
        loaded: (rooms) => rooms.isNotEmpty,
        orElse: () => false,
      );
      if (hadRooms) {
        _chatState.value = const ChatState.loaded(rooms: []);
        _selectedChatType.value = _selectedChatType.value;
        _lastUpdateTime = DateTime.now();
        return;
      }
      _chatState.value = const ChatState.loading();
      _emptyRoomListSettleTimer = Timer(_emptyListSettleDuration, () {
        if (!_isSubscribed || !context.mounted) return;
        _chatState.value = const ChatState.loaded(rooms: []);
        _selectedChatType.value = _selectedChatType.value;
      });
      _lastUpdateTime = DateTime.now();
      return;
    }

    _chatState.value = ChatState.loaded(rooms: list);
    _selectedChatType.value = _selectedChatType.value;
    _lastUpdateTime = DateTime.now();
  }

  void _listenToChatUpdates() {
    _roomListSubscription?.cancel();

    _roomListSubscription = model.subscribeToRoomList().listen(
      _onRoomList,
      onError: (error) {
        LoggingService.error(
          'CHAT_LISTING_SCREEN',
          'Error in room list stream: $error',
        );
        _scheduleReconnection();
      },
      onDone: () {
        LoggingService.info(
          'CHAT_LISTING_SCREEN',
          'Room list stream completed',
        );
        if (_isSubscribed) {
          _scheduleReconnection();
        }
      },
    );

    MatrixService().registerRoomUpdatesSubscription(_roomListSubscription!);
    _isSubscribed = true;
    _resetReconnectionAttempts();
    _startHealthCheck();
    LoggingService.info(
      'CHAT_LISTING_SCREEN',
      'Started listening to room list',
    );
  }

  void retry() {
    _loadAllChats();
  }

  void navigateToConversationScreen(
    BuildContext context,
    String chatId,
    String roomName,
    ChatRoomStatus status,
  ) {
    widget.navigateToConversationScreen(context, chatId, roomName, status);
  }

  void setSelectedChatType(ChatType type) {
    _selectedChatType.value = type;
  }

  Future<Uint8List?> loadListingThumbnail(String roomId, Message message) =>
      model.loadListingThumbnail(roomId, message);

  /// Pause room updates subscription when app goes to background
  void pauseRoomUpdates() {
    if (_roomListSubscription != null && _isSubscribed) {
      LoggingService.info(
        'CHAT_LISTING_SCREEN',
        'Pausing room updates subscription (app going to background)',
      );
      try {
        _roomListSubscription!.pause();
        _stopHealthCheck(); // Stop health checks while paused
      } catch (e) {
        LoggingService.error(
          'CHAT_LISTING_SCREEN',
          'Error pausing subscription: $e - will reconnect instead',
        );
        // If pause fails, cancel and will reconnect when resumed
        _roomListSubscription?.cancel();
        _roomListSubscription = null;
      }
    }
  }

  /// Resume room updates subscription when app comes to foreground
  void resumeRoomUpdates() {
    if (_isSubscribed) {
      LoggingService.info(
        'CHAT_LISTING_SCREEN',
        'Resuming room updates subscription (app coming to foreground)',
      );

      // Check if subscription is still valid
      if (_roomListSubscription != null) {
        try {
          _roomListSubscription!.resume();
          _startHealthCheck(); // Resume health checks
        } catch (e) {
          LoggingService.error(
            'CHAT_LISTING_SCREEN',
            'Error resuming subscription: $e - reconnecting instead',
          );
          // If resume fails, reconnect
          _listenToChatUpdates();
        }
      } else {
        // Subscription was lost, reconnect
        LoggingService.info(
          'CHAT_LISTING_SCREEN',
          'Subscription lost, reconnecting...',
        );
        _listenToChatUpdates();
      }
    }
  }

  /// Reconnect room updates subscription (useful after network issues)
  void reconnectRoomUpdates() {
    LoggingService.info(
      'CHAT_LISTING_SCREEN',
      'Reconnecting room updates subscription',
    );
    _listenToChatUpdates();
  }

  /// Check if room updates subscription is active
  bool get isRoomUpdatesActive =>
      _isSubscribed && _roomListSubscription != null;

  /// Get detailed connection status for debugging
  Map<String, dynamic> get connectionStatus {
    return {
      'isSubscribed': _isSubscribed,
      'hasSubscription': _roomListSubscription != null,
      'reconnectionAttempts': _reconnectionAttempts,
      'lastUpdateTime': _lastUpdateTime?.toIso8601String(),
      'timeSinceLastUpdate': _lastUpdateTime != null
          ? DateTime.now().difference(_lastUpdateTime!).inSeconds
          : null,
      'healthCheckActive': _healthCheckTimer != null,
      'reconnectionPending': _reconnectionTimer != null,
    };
  }

  /// Force refresh room updates subscription
  void refreshRoomUpdates() {
    LoggingService.info(
      'CHAT_LISTING_SCREEN',
      'Force refreshing room updates subscription',
    );
    // Cancel any pending reconnection attempts
    _reconnectionTimer?.cancel();
    _reconnectionAttempts = 0;
    _listenToChatUpdates();
  }

  /// Check connection health and reconnect if needed
  void checkConnectionHealth() {
    if (!_isSubscribed) return;

    final now = DateTime.now();
    final timeSinceLastUpdate = _lastUpdateTime != null
        ? now.difference(_lastUpdateTime!)
        : Duration.zero;

    LoggingService.info(
      'CHAT_LISTING_SCREEN',
      'Connection health check - Last update: ${timeSinceLastUpdate.inSeconds}s ago',
    );

    if (timeSinceLastUpdate > _healthCheckInterval) {
      LoggingService.info(
        'CHAT_LISTING_SCREEN',
        'Connection appears stale, forcing refresh',
      );
      refreshRoomUpdates();
    }
  }

  /// Restart sync service then resubscribe to room updates (e.g. after sync exited).
  Future<void> _restartSyncAndResubscribe() async {
    try {
      await MatrixService().client.restartSyncService();
      if (_isSubscribed) _listenToChatUpdates();
    } catch (e) {
      LoggingService.error('CHAT_LISTING_SCREEN', 'Failed to restart sync: $e');
      if (_isSubscribed) _scheduleReconnection();
    }
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnection() {
    if (!_isSubscribed) return;

    // Cancel any existing reconnection timer
    _reconnectionTimer?.cancel();

    // Calculate delay with exponential backoff
    final delay = Duration(
      seconds:
          (_initialReconnectionDelay.inSeconds * (1 << _reconnectionAttempts))
              .clamp(1, _maxReconnectionDelay.inSeconds),
    );

    LoggingService.info(
      'CHAT_LISTING_SCREEN',
      'Scheduling reconnection attempt ${_reconnectionAttempts + 1} in ${delay.inSeconds}s',
    );

    _reconnectionTimer = Timer(delay, () {
      if (_isSubscribed && _reconnectionAttempts < _maxReconnectionAttempts) {
        _reconnectionAttempts++;
        LoggingService.info(
          'CHAT_LISTING_SCREEN',
          'Attempting reconnection (attempt $_reconnectionAttempts)',
        );
        _restartSyncAndResubscribe();
      } else if (_reconnectionAttempts >= _maxReconnectionAttempts) {
        LoggingService.error(
          'CHAT_LISTING_SCREEN',
          'Max reconnection attempts reached. Manual intervention required.',
        );
        // Reset attempts for next manual refresh
        _reconnectionAttempts = 0;
      }
    });
  }

  /// Reset reconnection attempts (called on successful connection)
  void _resetReconnectionAttempts() {
    if (_reconnectionAttempts > 0) {
      LoggingService.info(
        'CHAT_LISTING_SCREEN',
        'Resetting reconnection attempts (was: $_reconnectionAttempts)',
      );
      _reconnectionAttempts = 0;
    }
  }

  /// Start periodic health checks to detect stream issues
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (timer) {
      if (!_isSubscribed) {
        timer.cancel();
        return;
      }

      // Check if we've received updates recently
      if (_lastUpdateTime != null) {
        final timeSinceLastUpdate = DateTime.now().difference(_lastUpdateTime!);
        if (timeSinceLastUpdate > _healthCheckInterval) {
          LoggingService.info(
            'CHAT_LISTING_SCREEN',
            'No room updates received for ${timeSinceLastUpdate.inSeconds}s, stream may be stale - scheduling reconnection',
          );
          // Force reconnection if stream appears stale
          _scheduleReconnection();
        }
      }
    });
  }

  /// Stop health check timer
  void _stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }
}
