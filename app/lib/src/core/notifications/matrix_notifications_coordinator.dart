import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/firebase_options.dart';
import 'package:matrix/src/core/domain/services/app_config.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix/src/core/calls/matrix_call_kit_coordinator.dart';
import 'package:matrix/src/core/matrix_app_lifecycle.dart';
import 'package:matrix/src/core/muted_chats_store.dart';
import 'package:matrix_sdk/matrix_sdk.dart';

const String _androidChannelId = 'matrix_messages';
const String _androidChannelName = 'Matrix';

/// iOS: base64 PushKit token for Sygnal + token refresh callbacks (see [AppDelegate.swift]).
const MethodChannel _voipMatrixPusherChannel =
    MethodChannel('dev.inve.matrixchat/voip_matrix_pusher');

const String _androidCallChannelId = 'matrix_incoming_calls';
const String _androidCallChannelName = 'Incoming calls';

/// [flutter_local_notifications] payload for taps / cold start (see [_onLocalNotificationResponse]).
const String _incomingCallPayloadPrefix = 'matrix_call_v1:';

/// Stable key so the OS stacks alerts per room (Android [groupKey], Apple [threadIdentifier]).
String _notificationGroupKey(String roomId) {
  final id = roomId.trim();
  if (id.isEmpty) return 'matrix_other';
  return 'matrix_room_$id';
}

/// Sygnal FCM v1 flattens event `content` as `content_*` strings ([matrix-org/sygnal](https://github.com/matrix-org/sygnal)).
bool _fcmDataLooksLikeRtcNotification(String typeField) {
  final t = typeField.trim().toLowerCase();
  if (t.isEmpty) return false;
  return t == 'm.rtc.notification' ||
      t.endsWith('.rtc.notification') ||
      t.contains('msc4075.rtc.notification');
}

/// `m.rtc.notification` uses `notification_type`: `ring` vs `notification` (no ring).
bool _fcmRtcNotificationIsRing(Map<String, String> data) {
  final flat = data['content_notification_type']?.toLowerCase();
  if (flat == 'ring') return true;
  if (flat == 'notification') return false;

  final content = data['content'];
  if (content != null && content.isNotEmpty) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map) {
        final nt = decoded['notification_type']?.toString().toLowerCase();
        if (nt == 'ring') return true;
        if (nt == 'notification') return false;
      }
    } catch (_) {}
  }
  return true;
}

/// FCM `data` values are string-like but typed as [Object] / [dynamic] in newer SDKs.
Map<String, String> _fcmDataAsStrings(Map<String, dynamic> data) {
  final out = <String, String>{};
  for (final e in data.entries) {
    out[e.key] = e.value?.toString() ?? '';
  }
  return out;
}

SyncNotificationSummary? _syncSummaryFromFcmData(Map<String, String> data) {
  final roomId = data['room_id']?.trim() ?? '';
  if (roomId.isEmpty) return null;
  var type = data['type']?.trim() ?? '';
  if (type.isEmpty) {
    type = data['content_msgtype']?.trim() ??
        data['content_type']?.trim() ??
        '';
  }
  if (!_fcmDataLooksLikeRtcNotification(type)) return null;

  final ring = _fcmRtcNotificationIsRing(data);
  final eventId = data['event_id']?.trim() ?? '';
  final sender = data['sender']?.trim() ?? '';
  final senderDn = data['sender_display_name']?.trim();
  final roomName = data['room_name']?.trim();
  final body = data['body']?.trim();

  return SyncNotificationSummary(
    roomId: roomId,
    roomDisplayName:
        roomName != null && roomName.isNotEmpty ? roomName : null,
    kind: SyncNotificationKind.incomingCall,
    senderId: sender,
    senderDisplayName:
        senderDn != null && senderDn.isNotEmpty ? senderDn : null,
    bodyPreview: body != null && body.isNotEmpty
        ? body
        : (ring ? 'Incoming call' : 'Call'),
    isHighlight: true,
    isNoisy: ring,
    eventId: eventId,
    incomingCallRing: ring,
  );
}

/// FCM background entrypoint (isolate). Keep logic minimal: no Matrix Rust.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background isolate: must use the same Firebase options as the main app or FCM→APNs fails.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await MatrixNotificationsCoordinator.showRemoteMessageStatic(
    message,
    fromFirebaseBackgroundHandler: true,
  );
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
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  String? _lastFcmToken;
  String? _lastVoipSygnalPushKey;

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

  /// Last [registerPusher] outcome this session (false until a successful registration).
  bool get isMatrixPushRegisteredOk => _matrixPushRegisteredOk;

  /// Re-fetches the FCM token and calls the homeserver [registerPusher] again.
  ///
  /// Use after fixing Sygnal, changing push app id, or recovering from a failed registration.
  /// No-op if [initialize] has not run (no [MatrixClient] bound).
  Future<void> refreshMatrixPusherRegistration() async {
    if (_client == null) return;
    await _registerPusherWithCurrentToken();
    await _registerVoipPusherWithCurrentKey();
  }

  static Future<void> showRemoteMessageStatic(
    RemoteMessage message, {
    bool fromFirebaseBackgroundHandler = false,
  }) async {
    await instance._ensureLocalPluginReady();
    await instance._showFromRemoteMessage(
      message,
      fromFirebaseBackgroundHandler: fromFirebaseBackgroundHandler,
    );
  }

  InitializationSettings _notificationInitSettings() {
    const androidInit = AndroidInitializationSettings('ic_stat_matrix');
    const darwinInit = DarwinInitializationSettings();
    return const InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );
  }

  /// The FCM background isolate calls [_ensureLocalPluginReady] without a tap handler; that can
  /// replace the main isolate callback. Re-bind after resume so tray / full-screen call taps work.
  Future<void> refreshLocalNotificationTapCallbackAfterResume() async {
    if (kIsWeb || _client == null) return;
    if (!_isAndroid() && !_isApple()) return;
    await _applyLocalNotificationTapCallback();
  }

  Future<void> _applyLocalNotificationTapCallback() async {
    try {
      await _local.initialize(
        _notificationInitSettings(),
        onDidReceiveNotificationResponse: _onLocalNotificationResponse,
      );
    } catch (e) {
      LoggingService.info(
        'MatrixNotifications',
        'local notification tap callback bind failed: $e',
      );
    }
  }

  /// Initializes the local notifications plugin and Android channels only.
  /// OS permission prompts (FCM / tray) run from [requestOsNotificationPermissions]
  /// so the app can show an in-app onboarding screen first.
  Future<void> _ensureLocalPluginReady() async {
    await _local.initialize(_notificationInitSettings());
    if (_isAndroid()) {
      const channel = AndroidNotificationChannel(
        _androidChannelId,
        _androidChannelName,
        description: 'Matrix messages and invites',
        importance: Importance.high,
      );
      const callChannel = AndroidNotificationChannel(
        _androidCallChannelId,
        _androidCallChannelName,
        description: 'Incoming Matrix calls when the app is in the background',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      );
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(channel);
      await android?.createNotificationChannel(callChannel);
    }
  }

  /// User-facing notification permission (FCM/APNs, Android POST_NOTIFICATIONS,
  /// local-notification plugin on Apple platforms). Safe to call more than once.
  Future<void> requestOsNotificationPermissions() async {
    if (kIsWeb) return;
    await _ensureLocalPluginReady();
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
    if (_isApple()) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      LoggingService.info(
        'MatrixNotifications',
        'Firebase notification permission: ${settings.authorizationStatus} '
        '(alert=${settings.alert}, badge=${settings.badge}, sound=${settings.sound})',
      );
    }
    if (_isAndroid()) {
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      try {
        await android?.requestFullScreenIntentPermission();
      } catch (e) {
        LoggingService.info(
          'MatrixNotifications',
          'requestFullScreenIntentPermission: $e',
        );
      }
    }
  }

  /// Call after [Firebase.initializeApp] and Matrix client is configured.
  Future<void> initialize({required MatrixClient client}) async {
    _client = client;
    await _ensureLocalPluginReady();
    await _applyLocalNotificationTapCallback();

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

    await _openedAppSubscription?.cancel();
    _openedAppSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      unawaited(_handleRemoteMessageOpenedFromBackground(message));
    });

    await _registerPusherWithCurrentToken();
    _bindIosVoipMatrixPusherChannel();
    await _registerVoipPusherWithCurrentKey();

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

    MatrixCallKitCoordinator.instance.bindClient(client);

    unawaited(_consumeColdStartNotificationLaunchTriggers());
  }

  void _onLocalNotificationResponse(NotificationResponse response) {
    if (response.notificationResponseType !=
        NotificationResponseType.selectedNotification) {
      return;
    }
    if (response.payload == null) return;
    final summary = _syncSummaryFromIncomingCallPayload(response.payload);
    if (summary == null) return;
    unawaited(MatrixCallKitCoordinator.instance.presentIncomingCall(summary));
  }

  Future<void> _consumeColdStartNotificationLaunchTriggers() async {
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        await _handleRemoteMessageOpenedFromBackground(initial);
      }
    } catch (e) {
      LoggingService.info('MatrixNotifications', 'getInitialMessage: $e');
    }

    try {
      final details = await _local.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) {
        final payload = details?.notificationResponse?.payload;
        final summary = _syncSummaryFromIncomingCallPayload(payload);
        if (summary != null) {
          await MatrixCallKitCoordinator.instance.presentIncomingCall(summary);
        }
      }
    } catch (e) {
      LoggingService.info(
        'MatrixNotifications',
        'getNotificationAppLaunchDetails: $e',
      );
    }
  }

  Future<void> _handleRemoteMessageOpenedFromBackground(
    RemoteMessage message,
  ) async {
    final data = _fcmDataAsStrings(message.data);
    await MutedChatsStore.instance.ensureLoaded();
    final roomId = data['room_id'] ?? '';
    if (roomId.isNotEmpty && MutedChatsStore.instance.isMuted(roomId)) {
      return;
    }
    final incoming = _syncSummaryFromFcmData(data);
    if (incoming == null || !incoming.incomingCallRing) return;
    await MatrixCallKitCoordinator.instance.presentIncomingCall(incoming);
  }

  Future<void> _onSyncNotification(SyncNotificationSummary s) async {
    await MutedChatsStore.instance.ensureLoaded();
    if (MutedChatsStore.instance.isMuted(s.roomId)) return;
    final key = s.eventId.isNotEmpty
        ? 'notif:${s.eventId}'
        : _syncSummaryDedupeKey(s);
    if (_isDuplicateWithinWindow(key)) return;

    if (s.kind == SyncNotificationKind.incomingCall && s.incomingCallRing) {
      unawaited(MatrixCallKitCoordinator.instance.presentIncomingCall(s));
    }

    if (MatrixAppLifecycle.isForeground) {
      if (s.kind != SyncNotificationKind.incomingCall) return;
      if (s.incomingCallRing) return;
    } else if (s.kind == SyncNotificationKind.incomingCall &&
        s.incomingCallRing) {
      return;
    }

    final title = s.roomDisplayName?.isNotEmpty == true
        ? s.roomDisplayName!
        : s.roomId;
    final who = s.senderDisplayName?.isNotEmpty == true
        ? s.senderDisplayName!
        : s.senderId;
    final body = switch (s.kind) {
      SyncNotificationKind.invite => 'Invite from $who',
      SyncNotificationKind.incomingCall =>
        s.bodyPreview.isNotEmpty ? s.bodyPreview : 'Call from $who',
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

  int _stableAndroidIncomingCallNotificationId(SyncNotificationSummary s) {
    if (s.eventId.isNotEmpty) {
      return s.eventId.hashCode & 0x7fffffff;
    }
    return _nextTrayNotificationId();
  }

  String _encodeIncomingCallPayload(SyncNotificationSummary s) {
    final map = <String, dynamic>{
      'roomId': s.roomId,
      'eventId': s.eventId,
      'roomName': s.roomDisplayName ?? s.roomId,
      'caller': s.senderDisplayName?.isNotEmpty == true
          ? s.senderDisplayName!
          : s.senderId,
      'ring': s.incomingCallRing,
    };
    return '$_incomingCallPayloadPrefix${base64Encode(utf8.encode(jsonEncode(map)))}';
  }

  SyncNotificationSummary? _syncSummaryFromIncomingCallPayload(String? payload) {
    if (payload == null || !payload.startsWith(_incomingCallPayloadPrefix)) {
      return null;
    }
    final b64 = payload.substring(_incomingCallPayloadPrefix.length);
    if (b64.isEmpty) return null;
    try {
      final raw = jsonDecode(utf8.decode(base64Decode(b64)));
      if (raw is! Map) return null;
      final roomId = raw['roomId']?.toString().trim() ?? '';
      if (roomId.isEmpty) return null;
      final eventId = raw['eventId']?.toString().trim() ?? '';
      final roomName = raw['roomName']?.toString().trim();
      final caller = raw['caller']?.toString().trim() ?? '';
      final ring = raw['ring'] == true;
      return SyncNotificationSummary(
        roomId: roomId,
        roomDisplayName:
            roomName != null && roomName.isNotEmpty ? roomName : null,
        kind: SyncNotificationKind.incomingCall,
        senderId: caller,
        senderDisplayName:
            caller.isNotEmpty ? caller : null,
        bodyPreview: ring ? 'Incoming call' : 'Call',
        isHighlight: true,
        isNoisy: ring,
        eventId: eventId,
        incomingCallRing: ring,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _showAndroidFullScreenIncomingCallFallback(
    SyncNotificationSummary incoming,
  ) async {
    if (!_isAndroid() || !incoming.incomingCallRing) return;

    final title = incoming.roomDisplayName?.isNotEmpty == true
        ? incoming.roomDisplayName!
        : incoming.roomId;
    final who = incoming.senderDisplayName?.isNotEmpty == true
        ? incoming.senderDisplayName!
        : incoming.senderId;
    final body =
        incoming.bodyPreview.isNotEmpty ? incoming.bodyPreview : 'Call from $who';

    final notificationId = _stableAndroidIncomingCallNotificationId(incoming);
    final android = AndroidNotificationDetails(
      _androidCallChannelId,
      _androidCallChannelName,
      channelDescription: 'Incoming Matrix calls when the app is in the background',
      icon: 'ic_stat_matrix',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: true,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
    );
    final details = NotificationDetails(android: android);
    await _local.show(
      notificationId,
      title,
      body,
      details,
      payload: _encodeIncomingCallPayload(incoming),
    );
  }

  Future<void> _showFromRemoteMessage(
    RemoteMessage message, {
    bool fromFirebaseBackgroundHandler = false,
  }) async {
    final data = _fcmDataAsStrings(message.data);
    await MutedChatsStore.instance.ensureLoaded();
    final roomId = data['room_id'] ?? '';
    if (roomId.isNotEmpty && MutedChatsStore.instance.isMuted(roomId)) {
      return;
    }

    final incoming = _syncSummaryFromFcmData(data);
    final dedupeKey = incoming != null && incoming.eventId.isNotEmpty
        ? 'notif:${incoming.eventId}'
        : (message.messageId != null && message.messageId!.isNotEmpty)
            ? 'fcm:id:${message.messageId}'
            : 'fcm:data:${message.data}';
    if (_isDuplicateWithinWindow(dedupeKey)) {
      return;
    }

    if (incoming != null) {
      if (incoming.incomingCallRing) {
        final present =
            MatrixCallKitCoordinator.instance.presentIncomingCall(incoming);
        if (fromFirebaseBackgroundHandler) {
          await present;
          await _showAndroidFullScreenIncomingCallFallback(incoming);
        } else {
          unawaited(present);
        }
        return;
      }
    }

    final n = message.notification;
    var title = n?.title ??
        data['title']?.toString() ??
        data['room_name']?.toString() ??
        'Matrix';
    var body = n?.body ??
        data['body']?.toString() ??
        data['content']?.toString() ??
        'New notification';
    if (incoming != null) {
      title = incoming.roomDisplayName?.isNotEmpty == true
          ? incoming.roomDisplayName!
          : incoming.roomId;
      final who = incoming.senderDisplayName?.isNotEmpty == true
          ? incoming.senderDisplayName!
          : incoming.senderId;
      body = incoming.bodyPreview.isNotEmpty
          ? incoming.bodyPreview
          : 'Call from $who';
    }
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
      icon: 'ic_stat_matrix',
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

  /// iOS: FCM registration token is not reliable until APNs has assigned a device token.
  Future<void> _waitForApnsDeviceToken() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    const step = Duration(milliseconds: 400);
    const maxWait = Duration(seconds: 30);
    final deadline = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(deadline)) {
      final apns = await FirebaseMessaging.instance.getAPNSToken();
      if (apns != null && apns.isNotEmpty) {
        LoggingService.info(
          'MatrixNotifications',
          'APNs token ok (len=${apns.length}), requesting FCM token…',
        );
        return;
      }
      await Future<void>.delayed(step);
    }
    LoggingService.info(
      'MatrixNotifications',
      'APNs token missing after ${maxWait.inSeconds}s — check Push capability, '
      'signing profile, and notification permission; FCM may stay null.',
    );
  }

  Future<void> _registerPusherWithCurrentToken() async {
    final c = _client;
    if (c == null) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _waitForApnsDeviceToken();
      }
      var token = await FirebaseMessaging.instance.getToken();
      if (token == null && defaultTargetPlatform == TargetPlatform.iOS) {
        for (var i = 0; i < 12 && token == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 750));
          token = await FirebaseMessaging.instance.getToken();
        }
      }
      _lastFcmToken = token;
      if (token != null) {
        final prefixLen = token.length > 24 ? 24 : token.length;
        LoggingService.info(
          'MatrixNotifications',
          'FCM token acquired (len=${token.length}, prefix=${token.substring(0, prefixLen)}…), '
          'registerPusher appId=${AppConfig.matrixPushAppId}',
        );
        await _registerPusher(c, pushKey: token);
      } else {
        LoggingService.info(
          'MatrixNotifications',
          'FCM getToken is null — cannot register Matrix pusher on this device.',
        );
      }
    } catch (e) {
      LoggingService.info(
        'MatrixNotifications',
        'FCM getToken failed (check Firebase config): $e',
      );
    }
  }

  void _bindIosVoipMatrixPusherChannel() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _voipMatrixPusherChannel.setMethodCallHandler((call) async {
      if (call.method == 'onVoipTokenUpdated') {
        final key = call.arguments as String?;
        if (key != null && key.isNotEmpty) {
          final c = _client;
          if (c != null) {
            unawaited(_registerVoipPusher(c, pushKey: key));
          }
        }
      } else if (call.method == 'onVoipTokenInvalidated') {
        unawaited(_unregisterVoipPusher());
      }
    });
  }

  Future<void> _registerVoipPusherWithCurrentKey() async {
    final c = _client;
    if (c == null || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    final url = AppConfig.matrixVoipPushGatewayUrl.trim();
    final appId = AppConfig.matrixVoipPushAppIdIos.trim();
    if (url.isEmpty || appId.isEmpty) return;
    try {
      final key =
          await _voipMatrixPusherChannel.invokeMethod('getSygnalVoipPushKey')
              as String?;
      if (key != null && key.isNotEmpty) {
        await _registerVoipPusher(c, pushKey: key);
      }
    } catch (e) {
      LoggingService.info(
        'MatrixNotifications',
        'VoIP Sygnal push key not available yet: $e',
      );
    }
  }

  Future<void> _registerVoipPusher(MatrixClient client, {required String pushKey}) async {
    final url = AppConfig.matrixVoipPushGatewayUrl.trim();
    final appId = AppConfig.matrixVoipPushAppIdIos.trim();
    if (url.isEmpty || appId.isEmpty) {
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
        appDisplayName: 'Matrix Terminal VoIP',
      );
      _lastVoipSygnalPushKey = pushKey;
      LoggingService.info(
        'MatrixNotifications',
        'registerPusher (VoIP/Sygnal) ok appId=$appId',
      );
    } catch (e) {
      LoggingService.info(
        'MatrixNotifications',
        'registerPusher (VoIP/Sygnal) failed: $e',
      );
    }
  }

  Future<void> _unregisterVoipPusher() async {
    final url = AppConfig.matrixVoipPushGatewayUrl.trim();
    final appId = AppConfig.matrixVoipPushAppIdIos.trim();
    final key = _lastVoipSygnalPushKey;
    final c = _client;
    if (c == null ||
        key == null ||
        url.isEmpty ||
        appId.isEmpty) {
      _lastVoipSygnalPushKey = null;
      return;
    }
    try {
      await c.unregisterPusher(pushKey: key, appId: appId);
    } catch (e) {
      LoggingService.info('MatrixNotifications', 'unregisterPusher (VoIP): $e');
    }
    _lastVoipSygnalPushKey = null;
  }

  Future<void> _registerPusher(MatrixClient client, {required String pushKey}) async {
    final url = AppConfig.matrixPushGatewayUrl.trim();
    final appId = AppConfig.matrixPushAppId.trim();
    if (url.isEmpty || appId.isEmpty) {
      _matrixPushRegisteredOk = false;
      LoggingService.info(
        'MatrixNotifications',
        'Skipping registerPusher (set MATRIX_PUSH_GATEWAY_URL + MATRIX_PUSH_APP_ID_IOS / MATRIX_PUSH_APP_ID_ANDROID in dart-define-from-file) — keeping sync active when minimized',
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      _voipMatrixPusherChannel.setMethodCallHandler(null);
    }

    await _syncSubscription?.cancel();
    _syncSubscription = null;
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    await _foregroundSubscription?.cancel();
    _foregroundSubscription = null;
    await _openedAppSubscription?.cancel();
    _openedAppSubscription = null;

    await _unregisterVoipPusher();

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
