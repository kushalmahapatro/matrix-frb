import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/src/core/desktop/desktop_ongoing_call_window_opener.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';

import 'native_livekit_call_session.dart';

/// How long [NativeLiveKitCallPhase.connecting] may last before the host reclaims the session.
///
/// Active calls ([connected]) are never touched. Incoming / outgoing / ringing flows that already
/// reached [connected] (including ring‑back with zero remotes) stay protected.
const Duration kNativeLiveKitHostStaleConnectingGrace = Duration(seconds: 90);

/// Global holder for the single native LiveKit call + whether the full-screen route is on top.
class NativeLiveKitCallHost extends ChangeNotifier {
  NativeLiveKitCallHost._() {
    Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(_reclaimStaleSessionIfNeeded());
    });
  }
  static final NativeLiveKitCallHost instance = NativeLiveKitCallHost._();

  NativeLiveKitCallSession? _session;
  bool _routeVisible = false;

  /// True while a [NativeLiveKitCallScreen] route is expected on the root navigator (pushed, not yet popped).
  bool _callScreenRouteOnStack = false;

  /// Hides the minimized banner between popping the call route and finishing [NativeLiveKitCallSession.hangUp] teardown.
  bool _suppressMinimizedBannerDuringHangUp = false;

  NativeLiveKitCallSession? get session => _session;
  bool get routeVisible => _routeVisible;

  /// Whether the full-screen call route may still be covering the app ([hangUp] should pop once).
  bool get callScreenRouteOnStack => _callScreenRouteOnStack;

  /// Minimized chrome: connected call, full UI not showing.
  bool get showMinimizedChrome =>
      _session != null &&
      !_routeVisible &&
      _session!.phase == NativeLiveKitCallPhase.connected &&
      !_suppressMinimizedBannerDuringHangUp;

  /// In-app strip (e.g. [NativeLiveKitMinimizedCallAppBarBottom]): desktop shows for the whole
  /// active call (connecting or connected) even while the auxiliary call window is open; mobile
  /// keeps the previous minimized-only behavior.
  bool get showInAppOngoingCallStrip {
    final s = _session;
    if (s == null || _suppressMinimizedBannerDuringHangUp) return false;
    final active = s.phase == NativeLiveKitCallPhase.connecting ||
        s.phase == NativeLiveKitCallPhase.connected;
    if (!active) return false;
    if (!kIsWeb && isDesktopTargetPlatform()) {
      return true;
    }
    return !_routeVisible && s.phase == NativeLiveKitCallPhase.connected;
  }

  /// Desktop ongoing-call popout: active call while the full Matrix call route is not on top.
  ///
  /// Includes [NativeLiveKitCallPhase.connecting] so a window can appear as soon as the
  /// session exists (after the user leaves the full-screen call UI, or if it was never shown).
  bool get showDesktopOngoingCallPopout {
    final s = _session;
    if (s == null || _suppressMinimizedBannerDuringHangUp) return false;
    if (_routeVisible) return false;
    return s.phase == NativeLiveKitCallPhase.connecting ||
        s.phase == NativeLiveKitCallPhase.connected;
  }

  void setSuppressMinimizedBannerDuringHangUp(bool value) {
    if (_suppressMinimizedBannerDuringHangUp == value) return;
    _suppressMinimizedBannerDuringHangUp = value;
    notifyListeners();
  }

  /// Ends any active call before starting another (avoids orphan Dart timers + Rust session races).
  ///
  /// Uses [timeout] so UI never hangs indefinitely if [NativeLiveKitCallSession.hangUp] stalls.
  Future<void> prepareForNewCall({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final existing = _session;
    if (existing == null) return;
    try {
      await existing
          .hangUp(historyEndReason: 'Replaced by new call')
          .timeout(timeout);
    } on TimeoutException {
      debugPrint(
        'NativeLiveKitCallHost.prepareForNewCall: hangUp timed out after $timeout',
      );
    } catch (e, st) {
      debugPrint('NativeLiveKitCallHost.prepareForNewCall: $e\n$st');
    }
    if (_session == existing) {
      detachSession(existing);
    }
  }

  void beginCall(NativeLiveKitCallSession session) {
    _session = session;
    _routeVisible = true;
    notifyListeners();
  }

  /// Drops a leaked host pointer when the session already finished teardown.
  ///
  /// Does **not** call [NativeLiveKitCallSession.hangUp] (no second teardown). Never runs for
  /// [NativeLiveKitCallPhase.connected] or in‑progress [connecting] within [kNativeLiveKitHostStaleConnectingGrace].
  Future<void> _reclaimStaleSessionIfNeeded() async {
    final s = _session;
    if (s == null) return;

    if (s.phase == NativeLiveKitCallPhase.connected) {
      return;
    }

    if (s.phase == NativeLiveKitCallPhase.ended) {
      detachSession(s);
      return;
    }

    if (s.phase != NativeLiveKitCallPhase.connecting) {
      return;
    }

    final elapsed = s.connectingElapsed;
    if (elapsed == null || elapsed < kNativeLiveKitHostStaleConnectingGrace) {
      return;
    }

    try {
      await s
          .hangUp(historyEndReason: 'Stale connecting session')
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      debugPrint(
        'NativeLiveKitCallHost: stale connect hangUp timed out after 25s',
      );
    } catch (e, st) {
      debugPrint('NativeLiveKitCallHost: stale connect reclaim: $e\n$st');
    }
    if (_session == s) {
      detachSession(s);
    }
  }

  /// Desktop: start the session without pushing [NativeLiveKitCallScreen] on the main navigator;
  /// the call UI lives in the auxiliary window ([DesktopOngoingCallWindowAttacher] opens it).
  ///
  /// Callers must also start media with [NativeLiveKitCallSession.ensureStarted] — the full-screen
  /// route is what normally invokes it.
  void beginCallDesktopDetached(NativeLiveKitCallSession session) {
    _session = session;
    _routeVisible = false;
    _callScreenRouteOnStack = false;
    notifyListeners();
  }

  void markRouteVisible(bool visible) {
    _routeVisible = visible;
    notifyListeners();
  }

  /// Desktop ongoing-call popout was closed from the OS chrome; clears stale opener state.
  void ongoingCallPopoutWindowWasClosedExternally() {
    notifyListeners();
  }

  /// Call immediately before [Navigator.push] of [NativeLiveKitCallScreen].
  void markCallScreenRouteOpening() {
    _callScreenRouteOnStack = true;
    notifyListeners();
  }

  /// Call when the call screen route is popped (back gesture, programmatic pop, etc.).
  void markCallScreenRouteClosed() {
    _callScreenRouteOnStack = false;
    notifyListeners();
  }

  @visibleForTesting
  void debugResetForTest() {
    _session = null;
    _routeVisible = false;
    _callScreenRouteOnStack = false;
    _suppressMinimizedBannerDuringHangUp = false;
    notifyListeners();
  }

  /// Binds [session] as active without starting navigation (unit tests only).
  @visibleForTesting
  void debugBindSessionForTest(NativeLiveKitCallSession session) {
    _session = session;
    _routeVisible = true;
    notifyListeners();
  }

  /// Clears the active session pointer after [session] has finished tearing down.
  void detachSession(NativeLiveKitCallSession ended) {
    if (_session != ended) return;
    unawaited(DesktopOngoingCallWindowOpener.closeActive());
    _session = null;
    _routeVisible = false;
    _callScreenRouteOnStack = false;
    _suppressMinimizedBannerDuringHangUp = false;
    notifyListeners();
  }
}
