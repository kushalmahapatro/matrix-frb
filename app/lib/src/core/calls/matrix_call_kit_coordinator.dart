import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:matrix/src/core/calls/call_history_store.dart';
import 'package:matrix/src/core/calls/incoming_call_banner_controller.dart';
import 'package:matrix/src/core/calls/incoming_call_present_dedupe.dart';
import 'package:matrix/src/core/calls/livekit_token_service.dart';
import 'package:matrix/src/core/calls/matrix_call_screen_route.dart';
import 'package:matrix/src/core/calls/matrix_incoming_callkit_show.dart';
import 'package:matrix/src/core/permissions/app_runtime_permissions.dart';
import 'package:matrix/src/core/calls/native_livekit_call_host.dart';
import 'package:matrix/src/features/settings/domain/profile_prefs.dart';
import 'package:matrix/src/core/calls/native_livekit_call_session.dart';
import 'package:matrix/src/core/notifications/missed_call_tray_notifier.dart';
import 'package:matrix/src/core/desktop/desktop_incoming_call_window_opener.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/domain/services/app_config.dart';
import 'package:matrix/src/core/navigation/app_navigation.dart';
import 'package:matrix_sdk/matrix_sdk.dart';
import 'package:uuid/uuid.dart';

class _PendingCall {
  _PendingCall({required this.roomId, required this.rtcEventId});

  final String roomId;
  final String rtcEventId;
}

class _DeferredIncomingAccept {
  _DeferredIncomingAccept({
    required this.roomId,
    required this.roomName,
    required this.voiceOnly,
    required this.preferVideoCallUi,
  });

  final String roomId;
  final String roomName;
  final bool voiceOnly;
  final bool preferVideoCallUi;
}

void _showLiveKitConfigSnack(String message) {
  final ctx = AppNavigation.rootNavigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;
  ScaffoldMessenger.maybeOf(
    ctx,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

/// Incoming MatrixRTC: **CallKit** (when configured) + in-app **banner** → answer screen → LiveKit.
///
/// VoIP Push (iOS): native PushKit still drives CallKit; Matrix VoIP pusher (Sygnal `*.voip` app_id) is
/// registered separately in [MatrixNotificationsCoordinator].
class MatrixCallKitCoordinator {
  MatrixCallKitCoordinator._();
  static final MatrixCallKitCoordinator instance = MatrixCallKitCoordinator._();

  final Map<String, _PendingCall> _byCallKitId = {};
  final IncomingCallPresentDedupe _presentDedupe = IncomingCallPresentDedupe();
  StreamSubscription<CallEvent?>? _eventSub;
  MatrixClient? _client;

  /// Accept arrived before [bindClient] (e.g. VoIP cold start). Flushed when the Matrix client is bound.
  _DeferredIncomingAccept? _deferredIncomingAccept;

  /// After Android cold-starts via [TransparentActivity] + accept intent, we open the call from
  /// [main] before the plugin event stream delivers [Event.actionCallAccept]; suppress one duplicate.
  DateTime? _suppressPluginAcceptUntil;

  void scheduleSuppressPluginAcceptDuplicate() {
    _suppressPluginAcceptUntil = DateTime.now().add(const Duration(seconds: 4));
  }

  bool _consumePluginAcceptIfSuppressed() {
    final until = _suppressPluginAcceptUntil;
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _suppressPluginAcceptUntil = null;
      return false;
    }
    _suppressPluginAcceptUntil = null;
    return true;
  }

  @visibleForTesting
  void debugClearPresentDedupeForTest() => _presentDedupe.clearDedupeEntries();

  void bindClient(MatrixClient client) {
    _client = client;
    // flutter_callkit_incoming has no macOS / Windows / Linux implementation;
    // subscribing throws MissingPluginException on those platforms.
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _eventSub ??= FlutterCallkitIncoming.onEvent.listen(_onCallKitEvent);
    unawaited(_flushDeferredIncomingAcceptIfReady());
    unawaited(_scheduleRecoverAcceptedCallIfMissed());
  }

  Future<void> _flushDeferredIncomingAcceptIfReady() async {
    final pending = _deferredIncomingAccept;
    final c = _client;
    if (pending == null || c == null) return;
    _deferredIncomingAccept = null;
    try {
      await openAcceptedIncomingNativeLiveKit(
        client: c,
        roomId: pending.roomId,
        roomName: pending.roomName,
        voiceOnly: pending.voiceOnly,
        preferVideoCallUi: pending.preferVideoCallUi,
      );
    } catch (e, st) {
      debugPrint(
        'MatrixCallKitCoordinator: deferred incoming accept failed: $e\n$st',
      );
    }
  }

  /// CallKit accept can run before the first [MaterialApp] frame attaches [AppNavigation.rootNavigatorKey].
  Future<NavigatorState?> _waitForRootNavigator({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final nav = AppNavigation.rootNavigatorKey.currentState;
      if (nav != null && nav.mounted) {
        return nav;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return AppNavigation.rootNavigatorKey.currentState;
  }

  void _onCallKitEvent(CallEvent? e) {
    if (e == null) return;
    final body = e.body;
    if (body is! Map) return;
    final bodyMap = Map<String, dynamic>.from(body);
    final id = bodyMap['id']?.toString();
    if (id == null) return;
    final pending = _byCallKitId[id];
    final extraRaw = bodyMap['extra'];
    Map<String, dynamic>? extra;
    if (extraRaw is Map) {
      extra = Map<String, dynamic>.from(extraRaw);
    }
    var roomId = pending?.roomId ?? '';
    var rtcEventId = pending?.rtcEventId ?? '';
    var roomName = '';
    if (extra != null) {
      roomId = roomId.isNotEmpty ? roomId : (extra['roomId']?.toString() ?? '');
      rtcEventId = rtcEventId.isNotEmpty
          ? rtcEventId
          : (extra['rtcEventId']?.toString() ?? '');
      roomName = extra['roomName']?.toString() ?? '';
    }
    roomName = roomName.isNotEmpty ? roomName : roomId;
    final client = _client;
    switch (e.event) {
      case Event.actionCallAccept:
        if (roomId.isNotEmpty && rtcEventId.isNotEmpty) {
          IncomingCallBannerController.instance.dismissIfMatches(
            roomId: roomId,
            rtcEventId: rtcEventId,
          );
        }
        final skipOpen = _consumePluginAcceptIfSuppressed();
        if (roomId.isNotEmpty && !skipOpen) {
          final c = _client;
          if (c != null) {
            unawaited(
              openAcceptedIncomingNativeLiveKit(
                client: c,
                roomId: roomId,
                roomName: roomName,
              ),
            );
          } else {
            _deferredIncomingAccept = _DeferredIncomingAccept(
              roomId: roomId,
              roomName: roomName,
              voiceOnly: true,
              preferVideoCallUi: false,
            );
            debugPrint(
              'MatrixCallKitCoordinator: CallKit accept before Matrix client bound; '
              'will join LiveKit when session is ready (room=$roomId).',
            );
          }
        }
        unawaited(FlutterCallkitIncoming.endCall(id));
        _byCallKitId.remove(id);
        break;
      case Event.actionCallDecline:
        if (roomId.isNotEmpty && rtcEventId.isNotEmpty) {
          IncomingCallBannerController.instance.dismissIfMatches(
            roomId: roomId,
            rtcEventId: rtcEventId,
          );
        }
        if (roomId.isNotEmpty && rtcEventId.isNotEmpty && client != null) {
          unawaited(
            client.declineRtcCall(
              roomId: roomId,
              rtcNotificationEventId: rtcEventId,
            ),
          );
        }
        if (roomId.isNotEmpty) {
          unawaited(
            CallHistoryStore.instance.appendIncomingCallOutcome(
              roomId: roomId,
              roomName: roomName,
              isDirectRoom: false,
              voiceOnly: true,
              endReason: 'Declined',
            ),
          );
        }
        _byCallKitId.remove(id);
        break;
      case Event.actionCallTimeout:
        // See [IncomingCallBannerController.shouldTreatCallKitTimeoutAsRealMissedCall].
        final realMiss = IncomingCallBannerController.instance
            .shouldTreatCallKitTimeoutAsRealMissedCall(
              roomId: roomId,
              rtcEventId: rtcEventId,
            );
        if (realMiss) {
          if (roomId.isNotEmpty && rtcEventId.isNotEmpty) {
            IncomingCallBannerController.instance.dismissIfMatches(
              roomId: roomId,
              rtcEventId: rtcEventId,
            );
          }
          if (roomId.isNotEmpty && rtcEventId.isNotEmpty && client != null) {
            unawaited(
              client.declineRtcCall(
                roomId: roomId,
                rtcNotificationEventId: rtcEventId,
              ),
            );
          }
          if (roomId.isNotEmpty) {
            unawaited(
              CallHistoryStore.instance.appendIncomingCallOutcome(
                roomId: roomId,
                roomName: roomName,
                isDirectRoom: false,
                voiceOnly: true,
                endReason: 'Missed call',
              ),
            );
            final callerLabel = bodyMap['nameCaller']?.toString();
            unawaited(
              MissedCallTrayNotifier.instance.showMissedCall(
                roomId: roomId,
                roomTitle: roomName.isNotEmpty ? roomName : null,
                callerLabel: (callerLabel != null && callerLabel.trim().isNotEmpty)
                    ? callerLabel.trim()
                    : null,
              ),
            );
          }
        } else {
          debugPrint(
            'MatrixCallKitCoordinator: ignored spurious CallKit TIMEOUT '
            '(id=$id room=$roomId)',
          );
        }
        _byCallKitId.remove(id);
        break;
      case Event.actionCallEnded:
        // Never dismiss the in-app banner or decline Matrix here. ENDED is noisy
        // (simulator, plugin lifecycle, after [endCall]); rely on DECLINE, real TIMEOUT,
        // or the 30s in-app timer instead.
        _byCallKitId.remove(id);
        break;
      default:
        break;
    }
  }

  /// Ends a native CallKit call if [callKitId] was stored with the ring (optional).
  Future<void> endCallKitIncomingIfStored(String? callKitId) async {
    if (callKitId == null || callKitId.isEmpty) return;
    try {
      await FlutterCallkitIncoming.endCall(callKitId);
    } catch (e) {
      debugPrint('MatrixCallKitCoordinator: endCall failed: $e');
    }
    _byCallKitId.remove(callKitId);
  }

  /// After the user accepts (answer screen or CallKit), join the LiveKit room.
  ///
  /// [voiceOnly]: join without publishing camera (audio-only / voice answer on a video ring).
  /// [preferVideoCallUi]: use the video call shell (e.g. self preview) even when [voiceOnly] is true.
  Future<void> openAcceptedIncomingNativeLiveKit({
    required MatrixClient client,
    required String roomId,
    required String roomName,
    bool voiceOnly = true,
    bool preferVideoCallUi = false,
  }) async {
    await _openNativeLiveKit(
      client: client,
      roomId: roomId,
      roomName: roomName,
      joinExistingCall: true,
      voiceOnly: voiceOnly,
      preferVideoCallUi: preferVideoCallUi,
    );
  }

  Future<void> _openNativeLiveKit({
    required MatrixClient client,
    required String roomId,
    required String roomName,
    required bool joinExistingCall,
    required bool voiceOnly,
    required bool preferVideoCallUi,
  }) async {
    var nav = AppNavigation.rootNavigatorKey.currentState;
    if (nav == null || !nav.mounted) {
      nav = await _waitForRootNavigator();
    }
    if (nav == null || !nav.mounted) {
      debugPrint(
        'MatrixCallKitCoordinator: root navigator not ready; cannot open incoming call.',
      );
      _showLiveKitConfigSnack(
        'Could not open the call — the app is still starting. Open the app and try again.',
      );
      return;
    }
    if (!AppConfig.isNativeLiveKitConfigurable) {
      debugPrint(
        'MatrixCallKitCoordinator: LiveKit not configured; cannot open incoming call.',
      );
      _showLiveKitConfigSnack(
        'LiveKit is not configured. Set LIVEKIT_URL and '
        'LIVEKIT_TOKEN_API_URL (or dev token / legacy fetch URL) in dart defines.',
      );
      return;
    }
    try {
      final creds = await LiveKitTokenService.resolve(
        matrixClient: client,
        matrixRoomId: roomId,
        voiceOnly: voiceOnly,
        joinExisting: joinExistingCall,
      );
      if (creds == null) {
        debugPrint(
          'MatrixCallKitCoordinator: token resolve returned null for $roomId',
        );
        _showLiveKitConfigSnack(
          'Could not get a LiveKit token. Check your token service and LIVEKIT_URL.',
        );
        return;
      }
      nav = AppNavigation.rootNavigatorKey.currentState;
      if (nav == null || !nav.mounted) return;
      final rootCtx = AppNavigation.rootNavigatorKey.currentContext;
      if (rootCtx != null && rootCtx.mounted) {
        if (voiceOnly) {
          final ok = await AppRuntimePermissions.ensureMicrophoneForVoiceCall(
            rootCtx,
          );
          if (!ok) return;
        } else {
          final ok = await AppRuntimePermissions.ensureCameraAndMicForVideoCall(
            rootCtx,
          );
          if (!ok) return;
        }
      }
      nav = AppNavigation.rootNavigatorKey.currentState;
      if (nav == null || !nav.mounted) return;
      await NativeLiveKitCallHost.instance.prepareForNewCall();
      nav = AppNavigation.rootNavigatorKey.currentState;
      if (nav == null || !nav.mounted) return;
      String? localDisplayName;
      try {
        final n = await client.getDisplayName();
        if (n != null && n.trim().isNotEmpty) {
          localDisplayName = n.trim();
        }
      } catch (_) {}
      final session = NativeLiveKitCallSession(
        NativeLiveKitCallArgs(
          matrixClient: client,
          livekitUrl: creds.url,
          accessToken: creds.token,
          title: roomName,
          matrixRoomId: roomId,
          voiceOnly: voiceOnly,
          preferVideoCallUi: preferVideoCallUi,
          localDisplayName: localDisplayName,
          localAvatarMxc: ProfilePrefs.instance.ownAvatarMxc,
          isDirectRoom: false,
          joinedExisting: joinExistingCall,
          historyDirection: CallHistoryDirection.incoming,
        ),
      );
      if (isDesktopTargetPlatform()) {
        NativeLiveKitCallHost.instance.beginCallDesktopDetached(session);
        await session.ensureStarted();
        return;
      }
      NativeLiveKitCallHost.instance.beginCall(session);
      NativeLiveKitCallHost.instance.markCallScreenRouteOpening();
      try {
        final pushNav = AppNavigation.rootNavigatorKey.currentState;
        if (pushNav == null || !pushNav.mounted) return;
        await pushNav.push<void>(matrixNativeLiveKitCallRoute());
      } finally {
        NativeLiveKitCallHost.instance.markCallScreenRouteClosed();
      }
    } catch (e, st) {
      debugPrint(
        'MatrixCallKitCoordinator: native LiveKit open failed: $e\n$st',
      );
    }
  }

  /// Register CallKit metadata so accept/decline events can resolve room + rtc id.
  void registerCallKitMapping({
    required String callKitId,
    required String roomId,
    required String rtcEventId,
  }) {
    _byCallKitId[callKitId] = _PendingCall(
      roomId: roomId,
      rtcEventId: rtcEventId,
    );
  }

  /// Tray / FCM tap on an **active ring**: join LiveKit immediately (no second in-app answer step).
  Future<void> acceptIncomingCallFromNotificationIfPossible(
    SyncNotificationSummary s,
  ) async {
    if (kIsWeb) return;
    if (s.kind != SyncNotificationKind.incomingCall) return;
    if (!s.incomingCallRing) return;
    final client = _client;
    if (client == null) return;
    if (s.roomId.trim().isEmpty || s.eventId.trim().isEmpty) return;
    final roomName = s.roomDisplayName?.trim().isNotEmpty == true
        ? s.roomDisplayName!.trim()
        : s.roomId;
    await openAcceptedIncomingNativeLiveKit(
      client: client,
      roomId: s.roomId,
      roomName: roomName,
    );
  }

  /// Non-blocking incoming UI: top banner; user opens answer screen from there (or uses CallKit).
  Future<void> presentIncomingCall(SyncNotificationSummary s) async {
    if (kIsWeb) return;
    if (s.kind != SyncNotificationKind.incomingCall) return;
    // Non-ring `m.rtc.notification` updates must not start or replace CallKit/banner —
    // that was causing instant ENDED / teardown right after a real ring.
    if (!s.incomingCallRing) return;

    final now = DateTime.now();
    if (!_presentDedupe.shouldPresentNow(s.eventId, now)) {
      return;
    }

    // iOS Simulator: CallKit + `CXEndCallAction` frequently emits bogus TIMEOUT/ENDED
    // (call not found in plugin manager). Matrix-driven rings use the in-app banner only.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final ios = await DeviceInfoPlugin().iosInfo;
        if (!ios.isPhysicalDevice) {
          IncomingCallBannerController.instance.show(s, callKitId: null);
          return;
        }
      } catch (e, st) {
        debugPrint('MatrixCallKitCoordinator: iosInfo for incoming: $e\n$st');
      }
    }

    final callKitId = const Uuid().v4();
    registerCallKitMapping(
      callKitId: callKitId,
      roomId: s.roomId,
      rtcEventId: s.eventId,
    );
    IncomingCallBannerController.instance.show(s, callKitId: callKitId);

    if (isDesktopTargetPlatform()) {
      final p = IncomingCallBannerController.instance.pending;
      if (p != null) {
        final dark =
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
        IncomingCallBannerController.instance.setDesktopRingWindowOpen(true);
        unawaited(
          DesktopIncomingCallWindowOpener.openFromPending(
            pending: p,
            isDarkMode: dark,
          ),
        );
      }
    }

    unawaited(showMatrixIncomingCallKit(callKitId: callKitId, s: s));
  }

  /// CallKit can deliver [Event.actionCallAccept] before Dart subscribes to the plugin event
  /// channel (cold start / resume). [FlutterCallkitIncoming.activeCalls] still reflects an
  /// answered call with `extra` — join LiveKit from that snapshot.
  Future<void> _scheduleRecoverAcceptedCallIfMissed() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    if (!AppConfig.isNativeLiveKitConfigurable) return;

    const delays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 500),
      Duration(milliseconds: 1800),
      Duration(milliseconds: 3800),
    ];
    for (final d in delays) {
      if (d > Duration.zero) {
        await Future<void>.delayed(d);
      }
      await _tryRecoverAcceptedCallIfMissedOnce();
    }
  }

  Future<void> _tryRecoverAcceptedCallIfMissedOnce() async {
    final client = _client;
    if (client == null) return;
    try {
      final raw = await FlutterCallkitIncoming.activeCalls();
      if (raw is! List) return;

      for (final item in raw) {
        if (item is! Map) continue;
        final m = _stringKeyedMapFromCallKit(Map<dynamic, dynamic>.from(item));

        final extra = _stringMapFromNested(m['extra']);
        final compliance = extra['matrixVoipPushCompliance'];
        if (compliance == 'true' || compliance == '1') continue;

        var roomId = extra['roomId']?.trim() ?? '';
        var rtcEventId = extra['rtcEventId']?.trim() ?? '';
        if (roomId.isEmpty || rtcEventId.isEmpty) continue;

        final accepted =
            _coerceTruthy(m['accepted']) || _coerceTruthy(m['isAccepted']);
        if (!accepted) continue;

        final sess = NativeLiveKitCallHost.instance.session;
        if (sess != null &&
            sess.args.matrixRoomId == roomId &&
            (sess.phase == NativeLiveKitCallPhase.connecting ||
                sess.phase == NativeLiveKitCallPhase.connected)) {
          return;
        }

        final roomName =
            extra['roomName']?.trim().isNotEmpty == true ? extra['roomName']!.trim() : roomId;
        final callKitId = m['id']?.toString().trim() ?? '';

        await openAcceptedIncomingNativeLiveKit(
          client: client,
          roomId: roomId,
          roomName: roomName,
        );
        if (callKitId.isNotEmpty) {
          await endCallKitIncomingIfStored(callKitId);
        }
        return;
      }
    } catch (e, st) {
      debugPrint(
        'MatrixCallKitCoordinator: recover accepted CallKit call: $e\n$st',
      );
    }
  }

  Map<String, dynamic> _stringKeyedMapFromCallKit(Map raw) {
    return Map<String, dynamic>.from(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  Map<String, String> _stringMapFromNested(Object? raw) {
    if (raw is! Map) return {};
    final out = <String, String>{};
    for (final e in raw.entries) {
      out[e.key.toString()] = e.value?.toString() ?? '';
    }
    return out;
  }

  bool _coerceTruthy(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase();
      return s == '1' || s == 'true' || s == 'yes';
    }
    return false;
  }
}

