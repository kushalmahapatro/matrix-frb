import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/src/core/calls/native_livekit_call_host.dart';
import 'package:matrix/src/core/calls/native_livekit_call_session.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/desktop/desktop_window_args.dart';

/// Auxiliary native window for ongoing calls (desktop).
///
/// The embedder assigns each window a random UUID ([WindowController.windowId]).
/// [desktopOngoingCallInstanceKey] in [DesktopWindowArgs] ties one window to one call.
abstract final class DesktopOngoingCallWindowOpener {
  static WindowController? _controller;
  static String? _activeInstanceKey;
  static StreamSubscription<void>? _windowsChangedSub;

  /// Serializes [ensureOpen] / [closeActive] so two overlapping calls cannot create two windows.
  static Future<void> _queue = Future.value();

  static Future<T> _enqueue<T>(Future<T> Function() fn) {
    final result = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        final v = await fn();
        if (!result.isCompleted) {
          result.complete(v);
        }
      } catch (e, st) {
        if (!result.isCompleted) {
          result.completeError(e, st);
        }
      }
    });
    return result.future;
  }

  static void _clearControllerState() {
    _controller = null;
    _activeInstanceKey = null;
  }

  static bool _isBenignCloseFailure(Object e) {
    if (e is WindowChannelException) {
      return e.code == 'CHANNEL_UNREGISTERED';
    }
    final s = e.toString();
    return s.contains('CHANNEL_UNREGISTERED');
  }

  static void _ensureWindowsChangedListener() {
    if (_windowsChangedSub != null) return;
    _windowsChangedSub = onWindowsChanged.listen((_) {
      unawaited(_reconcileAfterNativeWindowListChanged());
    });
  }

  static Future<void> _reconcileAfterNativeWindowListChanged() async {
    final c = _controller;
    if (c == null) return;
    try {
      final all = await WindowController.getAll();
      final stillThere = all.any((w) => w.windowId == c.windowId);
      if (!stillThere) {
        _clearControllerState();
        NativeLiveKitCallHost.instance
            .ongoingCallPopoutWindowWasClosedExternally();
      }
    } catch (e, st) {
      debugPrint('DesktopOngoingCallWindowOpener.reconcile: $e\n$st');
    }
  }

  /// Closes extra auxiliary engines for the same [callInstanceId] (defensive; mutex stops most races).
  static Future<void> _closeOtherOngoingWindowsWithSameInstance({
    required String keepWindowId,
    required String callInstanceId,
  }) async {
    if (callInstanceId.isEmpty) return;
    try {
      final all = await WindowController.getAll();
      for (final w in all) {
        if (w.windowId == keepWindowId) continue;
        final parsed = DesktopWindowArgs.tryParseOngoingCall(w.arguments);
        if (parsed != null && parsed.callInstanceId == callInstanceId) {
          try {
            await w.invokeMethod<void>('window_close');
          } catch (_) {}
        }
      }
    } catch (e, st) {
      debugPrint('DesktopOngoingCallWindowOpener.closeDuplicates: $e\n$st');
    }
  }

  static Future<void> ensureOpen(
    NativeLiveKitCallSession session, {
    required bool isDarkMode,
  }) {
    if (kIsWeb || !isDesktopTargetPlatform()) {
      return Future.value();
    }
    return _enqueue(() => _ensureOpenBody(session, isDarkMode: isDarkMode));
  }

  static Future<void> _ensureOpenBody(
    NativeLiveKitCallSession session, {
    required bool isDarkMode,
  }) async {
    _ensureWindowsChangedListener();

    final key = session.desktopOngoingCallInstanceKey;
    if (_controller != null && _activeInstanceKey == key) {
      try {
        final all = await WindowController.getAll();
        if (all.any((w) => w.windowId == _controller!.windowId)) {
          return;
        }
      } catch (_) {}
    }

    if (_controller != null) {
      await _closeActiveBody();
    }

    try {
      final c = await WindowController.create(
        WindowConfiguration(
          arguments: DesktopWindowArgs.encodeOngoingCall(
            isDarkMode: isDarkMode,
            voiceOnly: session.voiceOnly,
            preferVideoCallUi: session.preferVideoCallUi,
            title: session.title,
            roomId: session.args.matrixRoomId,
            callInstanceId: key,
          ),
          hiddenAtLaunch: false,
        ),
      );
      _controller = c;
      _activeInstanceKey = key;
      await c.show();
      await _closeOtherOngoingWindowsWithSameInstance(
        keepWindowId: c.windowId,
        callInstanceId: key,
      );
    } catch (e, st) {
      debugPrint('DesktopOngoingCallWindowOpener.ensureOpen: $e\n$st');
      _clearControllerState();
    }
  }

  /// Brings the auxiliary call window forward, recreating it if the user closed it.
  static Future<void> focusOrEnsureActiveCallWindow({
    required NativeLiveKitCallSession session,
    required bool isDarkMode,
  }) async {
    if (kIsWeb || !isDesktopTargetPlatform()) return;
    _ensureWindowsChangedListener();
    final key = session.desktopOngoingCallInstanceKey;

    final broughtForward = await _enqueue<bool>(() async {
      if (_controller != null && _activeInstanceKey == key) {
        try {
          final all = await WindowController.getAll();
          if (all.any((w) => w.windowId == _controller!.windowId)) {
            await _controller!.invokeMethod<void>('window_show');
            return true;
          }
        } catch (_) {}
        await _closeActiveBody();
      }
      return false;
    });

    if (broughtForward) return;

    await ensureOpen(session, isDarkMode: isDarkMode);
    await _enqueue<void>(() async {
      if (_controller != null) {
        try {
          await _controller!.invokeMethod<void>('window_show');
        } catch (_) {}
      }
    });
  }

  static Future<void> closeActive() {
    if (kIsWeb || !isDesktopTargetPlatform()) {
      return Future.value();
    }
    return _enqueue(_closeActiveBody);
  }

  static Future<void> _closeActiveBody() async {
    _activeInstanceKey = null;
    final c = _controller;
    final windowId = c?.windowId;
    _controller = null;
    if (c == null || windowId == null || windowId.isEmpty) return;

    try {
      final all = await WindowController.getAll();
      final stillThere = all.any((w) => w.windowId == windowId);
      if (!stillThere) {
        return;
      }
      await c.invokeMethod('window_close');
    } catch (e, st) {
      if (!_isBenignCloseFailure(e)) {
        debugPrint('DesktopOngoingCallWindowOpener.closeActive: $e\n$st');
      }
    }
  }
}
