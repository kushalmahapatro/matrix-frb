import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/src/core/domain/services/app_config.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix/src/core/matrix_app_lifecycle.dart';
import 'package:matrix_sdk/matrix_sdk.dart';

const String _androidChannelId = 'matrix_messages';
const String _androidChannelName = 'Matrix';

/// Stable key so the OS stacks alerts per room (Android [groupKey], Apple [threadIdentifier]).
String _notificationGroupKey(String roomId) {
  final id = roomId.trim();
  if (id.isEmpty) return 'matrix_other';
  return 'matrix_room_$id';
}

/// FCM background entrypoint (isolate). Keep logic minimal: no Matrix Rust.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await MatrixNotificationsCoordinator.showRemoteMessageStatic(message);
}

bool _isAndroid() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool _isApple() =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Matrix push registration, FCM, local notifications, and sync-notification stream.
class MatrixNotificationsCoordinator {
  MatrixNotificationsCoordinator._();
  static final MatrixNotificationsCoordinator instance =
      MatrixNotificationsCoordinator._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  MatrixClient? _client;
  StreamSubscription<SyncNotificationSummary>? _syncSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  String? _lastFcmToken;

  /// Monotonic id so Android does not replace every alert with the same tray slot
  /// (e.g. invites use empty [SyncNotificationSummary.eventId] → same hash as before).
  int _trayNotificationSerial = 0;

  /// Suppress duplicate delivery of the same event within a short window only.
  final Map<String, DateTime> _dedupeLastShown = {};
  static const Duration _dedupeWindow = Duration(seconds: 2);

  /// True only after [MatrixClient.registerPusher] succeeds at least once this session.
  /// Used to decide whether we may stop sync in background (FCM is expected to deliver).
  bool _matrixPushRegisteredOk = false;

  /// When true, [LifeCycleAwareWidget] may call [MatrixClient.pauseSyncService] on minimize.
  ///
  /// If push is not configured or registration failed, this stays false so **sliding sync keeps
  /// running** while the process is alive — otherwise minimized users would get no notifications
  /// (sync is stopped and FCM is not delivering).
  bool get shouldPauseBackgroundSync {
    final url = AppConfig.matrixPushGatewayUrl.trim();
    final appId = AppConfig.matrixPushAppId.trim();
    return url.isNotEmpty && appId.isNotEmpty && _matrixPushRegisteredOk;
  }

  static Future<void> showRemoteMessageStatic(RemoteMessage message) async {
    await instance._ensureLocalPluginReady();
    await instance._showFromRemoteMessage(message);
  }

  Future<void> _ensureLocalPluginReady() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const init = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _local.initialize(init);
    if (_isAndroid()) {
      const channel = AndroidNotificationChannel(
        _androidChannelId,
        _androidChannelName,
        description: 'Matrix messages and invites',
        importance: Importance.high,
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Separate from FCM: without this, plugin-posted alerts may not appear on iOS.
      await _local
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      await _local
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }
  }

  /// Call after [Firebase.initializeApp] and Matrix client is configured.
  Future<void> initialize({required MatrixClient client}) async {
    _client = client;
    await _ensureLocalPluginReady();

    if (_isApple()) {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    }
    if (_isAndroid()) {
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _foregroundSubscription ??=
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      unawaited(_showFromRemoteMessage(message));
    });

    await _registerPusherWithCurrentToken();
    _tokenRefreshSubscription ??=
        FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _lastFcmToken = token;
      final c = _client;
      if (c != null) {
        unawaited(_registerPusher(c, pushKey: token));
      }
    });

    _syncSubscription ??=
        client.subscribeToSyncNotifications().listen((summary) {
      unawaited(_onSyncNotification(summary));
    });
  }

  Future<void> _onSyncNotification(SyncNotificationSummary s) async {
    if (MatrixAppLifecycle.isForeground) return;
    final key = _syncSummaryDedupeKey(s);
    if (_isDuplicateWithinWindow(key)) return;
    final title = s.roomDisplayName?.isNotEmpty == true
        ? s.roomDisplayName!
        : s.roomId;
    final who = s.senderDisplayName?.isNotEmpty == true
        ? s.senderDisplayName!
        : s.senderId;
    final body = switch (s.kind) {
      SyncNotificationKind.invite => 'Invite from $who',
      _ => s.bodyPreview.isNotEmpty ? s.bodyPreview : 'New activity from $who',
    };
    await _showLocal(
      title: title,
      body: body,
      roomId: s.roomId,
    );
  }

  /// Invites (and some events) have no [SyncNotificationSummary.eventId]; include kind/sender/body
  /// so different events are not merged into one dedupe key forever.
  String _syncSummaryDedupeKey(SyncNotificationSummary s) {
    if (s.eventId.isNotEmpty) {
      return 'sync:${s.roomId}\u0001${s.eventId}';
    }
    return 'sync:${s.roomId}\u0001${s.kind.name}\u0001${s.senderId}\u0001${s.bodyPreview}';
  }

  bool _isDuplicateWithinWindow(String key) {
    final now = DateTime.now();
    if (_dedupeLastShown.length > 128) {
      _dedupeLastShown.removeWhere(
        (k, t) => now.difference(t) > const Duration(minutes: 1),
      );
    }
    final prev = _dedupeLastShown[key];
    if (prev != null && now.difference(prev) < _dedupeWindow) {
      return true;
    }
    _dedupeLastShown[key] = now;
    return false;
  }

  int _nextTrayNotificationId() {
    _trayNotificationSerial = (_trayNotificationSerial + 1) & 0x7fffffff;
    if (_trayNotificationSerial == 0) {
      _trayNotificationSerial = 1;
    }
    return _trayNotificationSerial;
  }

  Future<void> _showFromRemoteMessage(RemoteMessage message) async {
    final dedupeKey = (message.messageId != null && message.messageId!.isNotEmpty)
        ? 'fcm:id:${message.messageId}'
        : 'fcm:data:${message.data}';
    if (_isDuplicateWithinWindow(dedupeKey)) {
      return;
    }
    final n = message.notification;
    final data = message.data;
    final title = n?.title ??
        data['title']?.toString() ??
        data['room_name']?.toString() ??
        'Matrix';
    final body = n?.body ??
        data['body']?.toString() ??
        data['content']?.toString() ??
        'New notification';
    final roomId = data['room_id']?.toString() ?? '';
    await _showLocal(
      title: title,
      body: body,
      roomId: roomId,
    );
  }

  Future<void> _showLocal({
    required String title,
    required String body,
    required String roomId,
  }) async {
    final notificationId = _nextTrayNotificationId();
    final groupKey = _notificationGroupKey(roomId);
    final android = AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      channelDescription: 'Matrix messages and invites',
      importance: Importance.high,
      priority: Priority.high,
      groupKey: groupKey,
      setAsGroupSummary: false,
      groupAlertBehavior: GroupAlertBehavior.all,
    );
    final darwin = DarwinNotificationDetails(threadIdentifier: groupKey);
    final details = NotificationDetails(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );
    await _local.show(
      notificationId,
      title,
      body,
      details,
      payload: roomId.isNotEmpty ? roomId : null,
    );
  }

  Future<void> _registerPusherWithCurrentToken() async {
    final c = _client;
    if (c == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      _lastFcmToken = token;
      if (token != null) {
        await _registerPusher(c, pushKey: token);
      }
    } catch (e) {
      LoggingService.info(
        'MatrixNotifications',
        'FCM getToken failed (check Firebase config): $e',
      );
    }
  }

  Future<void> _registerPusher(MatrixClient client, {required String pushKey}) async {
    final url = AppConfig.matrixPushGatewayUrl.trim();
    final appId = AppConfig.matrixPushAppId.trim();
    if (url.isEmpty || appId.isEmpty) {
      _matrixPushRegisteredOk = false;
      LoggingService.info(
        'MatrixNotifications',
        'Skipping registerPusher (set MATRIX_PUSH_GATEWAY_URL + MATRIX_PUSH_APP_ID in dart-define-from-file) — keeping sync active when minimized',
      );
      return;
    }
    final deviceName = await _deviceDisplayName();
    try {
      await client.registerPusher(
        pushKey: pushKey,
        appId: appId,
        url: url,
        displayName: deviceName,
        profileTag: '',
        lang: WidgetsBinding.instance.platformDispatcher.locale.languageCode,
        appDisplayName: 'Matrix Terminal',
      );
      _matrixPushRegisteredOk = true;
      LoggingService.info(
        'MatrixNotifications',
        'registerPusher ok (background sync may pause when app minimized)',
      );
    } catch (e) {
      _matrixPushRegisteredOk = false;
      LoggingService.info(
        'MatrixNotifications',
        'registerPusher failed — sync will stay running in background for notifications: $e',
      );
    }
  }

  Future<String> _deviceDisplayName() async {
    if (kIsWeb) return 'Matrix web';
    try {
      final plugin = DeviceInfoPlugin();
      if (_isAndroid()) {
        final a = await plugin.androidInfo;
        return a.model;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final i = await plugin.iosInfo;
        return i.name;
      }
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        final m = await plugin.macOsInfo;
        return m.computerName;
      }
    } catch (_) {}
    return 'Matrix client';
  }

  /// Stop listeners and unregister pusher when logging out.
  Future<void> dispose() async {
    await _syncSubscription?.cancel();
    _syncSubscription = null;
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    await _foregroundSubscription?.cancel();
    _foregroundSubscription = null;

    final url = AppConfig.matrixPushGatewayUrl.trim();
    final appId = AppConfig.matrixPushAppId.trim();
    final token = _lastFcmToken;
    final c = _client;
    if (c != null &&
        token != null &&
        url.isNotEmpty &&
        appId.isNotEmpty) {
      try {
        await c.unregisterPusher(pushKey: token, appId: appId);
      } catch (e) {
        LoggingService.info('MatrixNotifications', 'unregisterPusher: $e');
      }
    }
    _lastFcmToken = null;
    _client = null;
    _dedupeLastShown.clear();
    _matrixPushRegisteredOk = false;
  }
}
