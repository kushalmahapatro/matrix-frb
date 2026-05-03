import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/domain/services/app_config.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix/src/core/media_library_log.dart';
import 'package:matrix/src/core/notifications/matrix_notifications_coordinator.dart';
import 'package:matrix/src/core/permissions/permission_onboarding_prefs.dart';
import 'package:matrix_sdk/matrix_sdk.dart' as platform;
import 'package:matrix_sdk/matrix_sdk.dart' as tracing;
import 'package:matrix_sdk/matrix_sdk.dart';
import 'package:result_dart/result_dart.dart';

class MatrixService {
  static final MatrixService _instance = MatrixService._internal();
  factory MatrixService() => _instance;
  MatrixService._internal();

  /// Not `late final`: [initialize] may run again when Splash is re-shown after logout.
  late MatrixClient _matrixClient;

  /// One active timeline subscription per room (timeline list or updates stream).
  final Map<String, StreamSubscription<Object?>> _timelineSubscriptions =
      <String, StreamSubscription<Object?>>{};

  /// Ephemeral typing user ids per room (from [MatrixClient.subscribeToRoomTyping]).
  /// Filled by [syncRoomTypingSubscriptions] for the messaging room list.
  final ValueNotifier<Map<String, List<String>>> roomListTypingUserIds =
      ValueNotifier<Map<String, List<String>>>(<String, List<String>>{});

  final Map<String, StreamSubscription<List<String>>> _roomTypingSubscriptions =
      <String, StreamSubscription<List<String>>>{};

  static const int _maxRoomTypingSubscriptions = 48;

  /// Drop typing UI if no fresh `m.typing` payload for this long (stale handler / missed EDUs).
  static const Duration _roomTypingTtl = Duration(seconds: 30);
  static const Duration _typingStalenessTick = Duration(seconds: 2);
  Timer? _roomTypingStalenessTimer;
  final Map<String, DateTime> _roomTypingLastPayloadAt = <String, DateTime>{};

  /// Single active room-updates subscription. Cancelling previous when a new
  /// one is registered. Typed as Object? so we can store `StreamSubscription<Chat>`
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
  bool _notificationsStarted = false;

  /// Directory passed to Rust [TracingFileConfiguration.path] after [initialize].
  /// Used for diagnostics (e.g. zipping rolling log files). Null until [initialize]
  /// has successfully called [platform.initPlatform].
  String? _rustLogsDirectory;
  String? get rustRollingLogsDirectory => _rustLogsDirectory;

  Future<Result<bool>> initialize({
    required String dbPath,
    required String logsPath,
    String? mediaCachePath,
    bool showHomeServerForUsername = true,
  }) async {
    if (_isInitialized) {
      return Success(true);
    }

    // Initialize Rust logging/.
    await LoggingService.init();
    final homeserverUrl = AppConfig.homeserverUrl;

    try {
      await platform.initPlatform(
        config: platform.TracingConfiguration(
          logLevel: tracing.LogLevel.error,
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
      _rustLogsDirectory = logsPath;
    } catch (e) {
      LoggingService.error('InitializationService', e.toString());
      return Failure(Exception(e.toString()));
    }

    LoggingService.info(
      'InitializationService',
      'Initializing Matrix app with homeserver: $homeserverUrl',
    );

    final config = ClientConfig(
      sessionPath: dbPath,
      homeserverUrl: homeserverUrl.toString(),
      passphrase: 'password',
      proxy: AppConfig.proxyUrl?.isNotEmpty ?? false
          ? AppConfig.proxyUrl
          : null,
      showHomeServerForUsername: showHomeServerForUsername,
      mediaCachePath: mediaCachePath,
    );

    try {
      final result = await MatrixClient.configure(config: config);
      _matrixClient = result;
      // Desktop: [Media.init] can block the UI isolate with synchronous native
      // work; [Future.timeout] then never runs. Skip eager init — first send /
      // transcode paths call [ensureMediaLibReady] anyway.
      if (!kIsWeb && isDesktopTargetPlatform()) {
        LoggingService.info(
          kMediaLibLogTag,
          'Skipping eager Media.init on desktop; loads on first media use.',
        );
      } else {
        try {
          await ensureMediaLibReady('app_startup_after_matrix_configure');
        } catch (e) {
          LoggingService.warn(
            kMediaLibLogTag,
            'init skipped after Matrix configure — video/image send prep may fail until media loads: $e',
          );
        }
      }
      _isInitialized = true;
      return Success(true);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  /// After [MatrixClient.startSyncService], registers FCM + Matrix pusher and subscribes to sync notifications.
  Future<void> startMatrixNotificationsIfReady() async {
    if (!_isInitialized || kIsWeb) return;
    try {
      final loggedIn = await _matrixClient.isClientAuthenticated();
      if (!loggedIn) return;
      if (_notificationsStarted) return;
      _notificationsStarted = true;
      await MatrixNotificationsCoordinator.instance.initialize(
        client: _matrixClient,
      );
    } catch (e) {
      _notificationsStarted = false;
      LoggingService.info(
        'MatrixService',
        'startMatrixNotificationsIfReady: $e',
      );
    }
  }

  Future<void> stopMatrixNotifications() async {
    if (!_notificationsStarted) return;
    _notificationsStarted = false;
    await MatrixNotificationsCoordinator.instance.dispose();
  }

  /// Re-runs FCM token retrieval and Matrix `POST /_matrix/client/v3/pushers/set` (registerPusher).
  ///
  /// Call after server-side push fixes, or if the user opened the app when registration had failed.
  /// If notifications were never started, runs [startMatrixNotificationsIfReady] first.
  Future<bool> refreshMatrixPushRegistration() async {
    if (!_isInitialized || kIsWeb) return false;
    try {
      final loggedIn = await _matrixClient.isClientAuthenticated();
      if (!loggedIn) return false;
      if (!_notificationsStarted) {
        await startMatrixNotificationsIfReady();
      } else {
        await MatrixNotificationsCoordinator.instance.refreshMatrixPusherRegistration();
      }
      return MatrixNotificationsCoordinator.instance.isMatrixPushRegisteredOk;
    } catch (e) {
      LoggingService.info('MatrixService', 'refreshMatrixPushRegistration: $e');
      return false;
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

  /// Best-effort pause of sliding sync before server logout. [SyncService::stop] can wait
  /// indefinitely if sync HTTP is stuck, so this is bounded.
  static const Duration _signOutPauseSyncTimeout = Duration(seconds: 3);

  /// Server `POST /logout` can hang on bad networks; bound so the UI is not stuck forever.
  static const Duration _signOutServerTimeout = Duration(seconds: 25);

  /// Ends Matrix session on the server, clears local session file (Rust), pauses sync,
  /// and tears down Dart-side subscriptions. Call before navigating back to Splash/login.
  Future<Result<bool>> signOut() async {
    if (!_isInitialized) {
      return Success(true);
    }
    disposeAllSubscriptions();
    try {
      try {
        await _matrixClient
            .pauseSyncService()
            .timeout(_signOutPauseSyncTimeout);
      } catch (_) {
        // Sync not started, stop timed out, or stop failed — still try server logout.
      }
      await _matrixClient.logout().timeout(_signOutServerTimeout);
    } on TimeoutException {
      return Failure(
        Exception(
          'Sign out timed out. Check your network and try again.',
        ),
      );
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
    await PermissionOnboardingPrefs.clearForLogout();
    return Success(true);
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

  /// Subscribes to `m.typing` for [orderedRoomIds] (capped) for the chat list preview.
  /// Order matters: earlier ids get subscriptions first when over the cap.
  /// Drops subscriptions for rooms no longer in the set.
  void syncRoomTypingSubscriptions(List<String> orderedRoomIds) {
    if (!_isInitialized) return;
    final seen = <String>{};
    final prioritized = <String>[];
    for (final id in orderedRoomIds) {
      if (id.isEmpty || !seen.add(id)) continue;
      prioritized.add(id);
    }
    final want = prioritized.toSet();
    for (final id in _roomTypingSubscriptions.keys.toList()) {
      if (!want.contains(id)) {
        _roomTypingSubscriptions.remove(id)?.cancel();
        final m = Map<String, List<String>>.from(roomListTypingUserIds.value);
        m.remove(id);
        roomListTypingUserIds.value = m;
      }
    }
    for (final id in prioritized) {
      if (_roomTypingSubscriptions.containsKey(id)) continue;
      // [ConversationScreen] subscribes to the same room’s typing stream; skip here
      // so Rust does not register duplicate `m.typing` handlers per room.
      if (_timelineSubscriptions.containsKey(id)) continue;
      if (_roomTypingSubscriptions.length >= _maxRoomTypingSubscriptions) {
        break;
      }
      try {
        _roomTypingSubscriptions[id] =
            _matrixClient.subscribeToRoomTyping(roomId: id).listen(
          (ids) {
            applyRoomTypingPayload(id, ids);
          },
          onError: (_) {
            _roomTypingSubscriptions.remove(id)?.cancel();
            applyRoomTypingPayload(id, const []);
          },
        );
      } catch (_) {}
    }
  }

  void clearRoomTypingSubscriptions() {
    for (final s in _roomTypingSubscriptions.values) {
      s.cancel();
    }
    _roomTypingSubscriptions.clear();
    _roomTypingStalenessTimer?.cancel();
    _roomTypingStalenessTimer = null;
    _roomTypingLastPayloadAt.clear();
    roomListTypingUserIds.value = <String, List<String>>{};
  }

  /// Updates per-room typing from the Rust `m.typing` stream. Refreshes TTL; clears stale
  /// rooms in the background after [_roomTypingTtl] without a payload.
  void applyRoomTypingPayload(String roomId, List<String> userIds) {
    if (roomId.isEmpty) return;
    _roomTypingStalenessTimer ??=
        Timer.periodic(_typingStalenessTick, _purgeStaleRoomTyping);
    if (userIds.isEmpty) {
      _roomTypingLastPayloadAt.remove(roomId);
    } else {
      _roomTypingLastPayloadAt[roomId] = DateTime.now();
    }
    final m = Map<String, List<String>>.from(roomListTypingUserIds.value);
    if (userIds.isEmpty) {
      m.remove(roomId);
    } else {
      m[roomId] = List<String>.from(userIds);
    }
    roomListTypingUserIds.value = m;
    if (roomListTypingUserIds.value.isEmpty) {
      _roomTypingStalenessTimer?.cancel();
      _roomTypingStalenessTimer = null;
    }
  }

  void _purgeStaleRoomTyping(Timer _) {
    final now = DateTime.now();
    final m = Map<String, List<String>>.from(roomListTypingUserIds.value);
    var changed = false;
    for (final roomId in m.keys.toList()) {
      final t = _roomTypingLastPayloadAt[roomId];
      if (t == null || now.difference(t) > _roomTypingTtl) {
        m.remove(roomId);
        _roomTypingLastPayloadAt.remove(roomId);
        changed = true;
      }
    }
    if (changed) {
      roomListTypingUserIds.value = m;
    }
    if (roomListTypingUserIds.value.isEmpty) {
      _roomTypingStalenessTimer?.cancel();
      _roomTypingStalenessTimer = null;
    }
  }

  /// Cancels all active subscriptions (room updates and timeline per room).
  /// Call on logout or app shutdown to avoid leaks and stop Rust streams.
  void disposeAllSubscriptions() {
    clearRoomTypingSubscriptions();
    unregisterRoomUpdatesSubscription();
    for (final roomId in _timelineSubscriptions.keys.toList()) {
      unregisterTimelineSubscription(roomId);
    }
    unawaited(stopMatrixNotifications());
  }
}
