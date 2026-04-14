import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/src/core/calls/incoming_call_banner_controller.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/desktop/desktop_window_args.dart';

/// Opens the auxiliary native window for an incoming MatrixRTC ring (desktop).
abstract final class DesktopIncomingCallWindowOpener {
  static WindowController? _controller;

  static Future<void> openFromPending({
    required PendingIncomingCallRing pending,
    required bool isDarkMode,
  }) async {
    if (kIsWeb || !isDesktopTargetPlatform()) return;
    await closeActive();
    try {
      final c = await WindowController.create(
        WindowConfiguration(
          arguments: DesktopWindowArgs.encodeIncomingCall(
            roomId: pending.roomId,
            rtcEventId: pending.rtcEventId,
            roomName: pending.roomName,
            callerLabel: pending.callerLabel,
            callKitId: pending.callKitId,
            isDarkMode: isDarkMode,
          ),
          hiddenAtLaunch: false,
        ),
      );
      _controller = c;
      await c.show();
    } catch (e, st) {
      debugPrint('DesktopIncomingCallWindowOpener.open: $e\n$st');
      IncomingCallBannerController.instance.setDesktopRingWindowOpen(false);
    }
  }

  static Future<void> closeActive() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      await c.invokeMethod('window_close');
    } catch (e, st) {
      debugPrint('DesktopIncomingCallWindowOpener.closeActive: $e\n$st');
    }
  }
}
