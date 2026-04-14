import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:matrix/src/core/calls/call_history_store.dart';
import 'package:matrix/src/core/desktop/incoming_call_desktop_hooks.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix_sdk/matrix_sdk.dart';

/// Holds a non-blocking incoming MatrixRTC ring: banner UI + auto-decline timer.
class IncomingCallBannerController extends ChangeNotifier {
  IncomingCallBannerController._();
  static final IncomingCallBannerController instance =
      IncomingCallBannerController._();

  PendingIncomingCallRing? _pending;

  /// Set when [show] runs; used to ignore spurious CallKit `ENDED` right after show.
  DateTime? _pendingShownAt;
  Timer? _autoDeclineTimer;

  /// True while the full-screen incoming answer UI is open (or being pushed). Hides
  /// the banner and prevents stacking duplicate answer routes.
  bool _incomingAnswerRouteActive = false;

  /// True while a separate native incoming-call window is shown (desktop); hides the main-window strip.
  bool _desktopRingWindowOpen = false;

  PendingIncomingCallRing? get pending => _pending;

  bool get incomingAnswerRouteActive => _incomingAnswerRouteActive;

  /// Whether the top incoming strip should be shown (pending ring, answer UI not in front).
  ///
  /// Desktop may also show a small native ring window; the main-window strip stays visible
  /// so users still see the banner in the primary window.
  bool get shouldShowIncomingStrip =>
      _pending != null && !_incomingAnswerRouteActive;

  void setDesktopRingWindowOpen(bool value) {
    if (_desktopRingWindowOpen == value) return;
    _desktopRingWindowOpen = value;
    notifyListeners();
  }

  void setIncomingAnswerRouteActive(bool value) {
    if (_incomingAnswerRouteActive == value) return;
    _incomingAnswerRouteActive = value;
    notifyListeners();
  }

  @visibleForTesting
  void debugClearForTest() {
    _autoDeclineTimer?.cancel();
    _autoDeclineTimer = null;
    _pending = null;
    _pendingShownAt = null;
    _incomingAnswerRouteActive = false;
    _desktopRingWindowOpen = false;
    unawaited(closeDesktopIncomingRingWindowIfAny());
    notifyListeners();
  }

  /// Shows or replaces the current incoming banner and restarts the auto-decline timer.
  void show(SyncNotificationSummary s, {String? callKitId}) {
    if (s.kind != SyncNotificationKind.incomingCall) return;
    _autoDeclineTimer?.cancel();
    _autoDeclineTimer = null;

    final roomName = s.roomDisplayName ?? s.roomId;
    final caller = s.senderDisplayName?.isNotEmpty == true
        ? s.senderDisplayName!
        : s.senderId;

    _pending = PendingIncomingCallRing(
      roomId: s.roomId,
      rtcEventId: s.eventId,
      roomName: roomName,
      callerLabel: caller,
      callKitId: callKitId,
    );
    _pendingShownAt = DateTime.now();

    _autoDeclineTimer = Timer(const Duration(seconds: 30), _onAutoDecline);
    notifyListeners();
  }

  void dismiss() {
    _autoDeclineTimer?.cancel();
    _autoDeclineTimer = null;
    _desktopRingWindowOpen = false;
    unawaited(closeDesktopIncomingRingWindowIfAny());
    if (_pending == null) return;
    final callKitId = _pending!.callKitId;
    _pending = null;
    _pendingShownAt = null;
    notifyListeners();
    if (callKitId != null && callKitId.isNotEmpty) {
      unawaited(FlutterCallkitIncoming.endCall(callKitId));
    }
  }

  /// Stops the 30s banner timeout while the user is on the answer screen (that screen has its own timer).
  void pauseAutoDeclineTimer() {
    _autoDeclineTimer?.cancel();
    _autoDeclineTimer = null;
  }

  /// Restarts the banner timeout if the user left the answer screen without accepting/declining.
  void resumeAutoDeclineIfStillPending() {
    if (_pending == null) return;
    _autoDeclineTimer?.cancel();
    _autoDeclineTimer = Timer(const Duration(seconds: 30), _onAutoDecline);
  }

  /// Whether an [Event.actionCallTimeout] from CallKit should end the Matrix ring.
  ///
  /// On the iOS Simulator, `CXEndCallAction` often fires with no matching call in the
  /// plugin's manager; the native code then emits **TIMEOUT** instead of DECLINE. Treating
  /// that as a missed call immediately calls [MatrixClient.declineRtcCall] and removes the
  /// banner. Ignore TIMEOUT if the same ring only just appeared ([_pendingShownAt]).
  bool shouldTreatCallKitTimeoutAsRealMissedCall({
    required String roomId,
    required String rtcEventId,
    Duration minRingVisible = const Duration(seconds: 5),
  }) {
    if (roomId.isEmpty || rtcEventId.isEmpty) return false;
    final p = _pending;
    if (p == null) return false;
    if (p.roomId != roomId || p.rtcEventId != rtcEventId) return false;
    final shown = _pendingShownAt;
    if (shown == null) return true;
    return DateTime.now().difference(shown) >= minRingVisible;
  }

  /// When the user answers from system CallKit, hide the in-app banner for the same ring.
  void dismissIfMatches({required String roomId, required String rtcEventId}) {
    final p = _pending;
    if (p == null) return;
    if (p.roomId == roomId && p.rtcEventId == rtcEventId) {
      dismiss();
    }
  }

  Future<void> _onAutoDecline() async {
    _autoDeclineTimer?.cancel();
    _autoDeclineTimer = null;
    _desktopRingWindowOpen = false;
    unawaited(closeDesktopIncomingRingWindowIfAny());
    final p = _pending;
    if (p == null) return;
    _pending = null;
    _pendingShownAt = null;
    notifyListeners();

    final ck = p.callKitId;
    if (ck != null && ck.isNotEmpty) {
      unawaited(FlutterCallkitIncoming.endCall(ck));
    }

    final client = MatrixService().client;
    if (p.roomId.isNotEmpty && p.rtcEventId.isNotEmpty) {
      try {
        await client.declineRtcCall(
          roomId: p.roomId,
          rtcNotificationEventId: p.rtcEventId,
        );
      } catch (e, st) {
        debugPrint('IncomingCallBannerController auto-decline: $e\n$st');
      }
    }
    if (p.roomId.isNotEmpty) {
      unawaited(
        CallHistoryStore.instance.appendIncomingCallOutcome(
          roomId: p.roomId,
          roomName: p.roomName,
          isDirectRoom: false,
          voiceOnly: true,
          endReason: 'Missed call',
        ),
      );
    }
  }
}

class PendingIncomingCallRing {
  const PendingIncomingCallRing({
    required this.roomId,
    required this.rtcEventId,
    required this.roomName,
    required this.callerLabel,
    this.callKitId,
  });

  final String roomId;
  final String rtcEventId;
  final String roomName;
  final String callerLabel;
  final String? callKitId;
}
