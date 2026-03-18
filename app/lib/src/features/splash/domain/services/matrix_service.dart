import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/src/core/domain/services/app_config.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix_sdk/matrix_sdk.dart' as platform;
import 'package:matrix_sdk/matrix_sdk.dart' as tracing;
import 'package:matrix_sdk/matrix_sdk.dart';
import 'package:result_dart/result_dart.dart';

class MatrixService {
  static final MatrixService _instance = MatrixService._internal();
  factory MatrixService() => _instance;
  MatrixService._internal();

  late final MatrixClient _matrixClient;

  /// rhttp client created before Matrix so Matrix SDK can use the same HTTP client (when native build uses rhttp-client feature). Kept so it is not GC'd.
  // ignore: unused_field
  late final RhttpClient _httpClient;

  /// One active timeline subscription per room (timeline list or updates stream).
  final Map<String, StreamSubscription<Object?>> _timelineSubscriptions =
      <String, StreamSubscription<Object?>>{};

  /// Single active room-updates subscription. Cancelling previous when a new
  /// one is registered. Typed as Object? so we can store StreamSubscription<Chat>
  /// from the chat listing screen (which maps RoomUpdate to Chat).
  StreamSubscription<Object?>? _roomUpdatesSubscription;

  /// Sink for optimistic room updates (e.g. after sending a message).
  /// Chat listing should merge this with subscribeToAllRoomUpdates().
  final StreamController<RoomUpdate> _roomUpdateSink =
      StreamController<RoomUpdate>.broadcast();
  Stream<RoomUpdate> get roomUpdatesStream => _roomUpdateSink.stream;

  void pushRoomUpdate(RoomUpdate update) {
    if (!_roomUpdateSink.isClosed) {
      _roomUpdateSink.add(update);
    }
  }

  MatrixClient get client => _matrixClient;
  bool get isInitialized => _isInitialized;
  bool _isInitialized = false;

  Future<Result<bool>> initialize({
    required String dbPath,
    required String logsPath,
  }) async {
    // Initialize Rust logging
    await LoggingService.init();
    final homeserverUrl = AppConfig.homeserverUrl;

    try {
      await platform.initPlatform(
        config: platform.TracingConfiguration(
          logLevel: tracing.LogLevel.trace,
          traceLogPacks: platform.TraceLogPacks.values,
          extraTargets: [],
          writeToStdoutOrSystem: true,
          writeToFiles: platform.TracingFileConfiguration(
            path: logsPath,
            filePrefix: 'matrix',
            fileSuffix: '.log',
            rotation: platform.FileRotation.daily,
            maxFiles: BigInt.from(10),
          ),
        ),
        useLightweightTokioRuntime: false,
      );

      // On iOS simulator, Rust tracing logs don't show in Dart VM console; stream and print.
      if (kDebugMode && defaultTargetPlatform == TargetPlatform.iOS) {
        platform.subscribeTracingLogs().listen((line) {
          debugPrint(line);
        });
      }
    } catch (e) {
      LoggingService.error('InitializationService', e.toString());
      return Failure(Exception(e.toString()));
    }

    LoggingService.info(
      'InitializationService',
      'Initializing Matrix app with homeserver: $homeserverUrl',
    );

    // Create rhttp client with interceptor so Matrix HTTP requests are logged (console + optional DevTools).
    try {
      _httpClient = await RhttpClient.create();
    } catch (e) {
      LoggingService.error(
        'InitializationService',
        'Could not create rhttp client (Matrix will use its own HTTP client): $e',
      );
      throw Exception(e.toString());
    }

    final config = ClientConfig(
      sessionPath: dbPath,
      homeserverUrl: homeserverUrl.toString(),
      passphrase: 'password',
      rhttpClient: _httpClient.ref,
      proxy: AppConfig.proxyEnabled ? AppConfig.proxyUrl : null,
    );

    try {
      final result = await MatrixClient.configure(config: config);
      _matrixClient = result;
      _isInitialized = true;
      return Success(true);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  Future<Result<bool>> isUserLoggedIn() async {
    try {
      final result = await _matrixClient.isClientAuthenticated();
      return Success(result);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  /// Registers the only active timeline subscription for [roomId]. Cancels any
  /// previous subscription for the same room (e.g. from a previous screen or
  /// before restart). Call [unregisterTimelineSubscription] when disposing.
  void registerTimelineSubscription(
    String roomId,
    StreamSubscription<Object?> subscription,
  ) {
    _timelineSubscriptions[roomId]?.cancel();
    _timelineSubscriptions[roomId] = subscription;
  }

  /// Unregisters the timeline subscription for [roomId]. Call from WM dispose.
  void unregisterTimelineSubscription(String roomId) {
    _timelineSubscriptions.remove(roomId)?.cancel();
  }

  /// Cancels any existing timeline subscription for [roomId]. Call before
  /// creating a new subscription (e.g. on re-subscribe) to avoid duplicate streams.
  void cancelTimelineSubscriptionForRoom(String roomId) {
    _timelineSubscriptions.remove(roomId)?.cancel();
  }

  /// Registers the only active room-updates subscription. Cancels any previous
  /// one. Call [unregisterRoomUpdatesSubscription] when disposing.
  void registerRoomUpdatesSubscription(
    StreamSubscription<Object?> subscription,
  ) {
    _roomUpdatesSubscription?.cancel();
    _roomUpdatesSubscription = subscription;
  }

  /// Unregisters the room-updates subscription and cancels it so the Rust stream
  /// stops and no message is missed only while subscribed. Call from WM dispose.
  void unregisterRoomUpdatesSubscription() {
    _roomUpdatesSubscription?.cancel();
    _roomUpdatesSubscription = null;
  }

  /// Cancels all active subscriptions (room updates and timeline per room).
  /// Call on logout or app shutdown to avoid leaks and stop Rust streams.
  void disposeAllSubscriptions() {
    unregisterRoomUpdatesSubscription();
    for (final roomId in _timelineSubscriptions.keys.toList()) {
      unregisterTimelineSubscription(roomId);
    }
  }
}
