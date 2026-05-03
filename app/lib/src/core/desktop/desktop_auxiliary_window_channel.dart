import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// [WindowController.invokeMethod] (e.g. `window_close`) is handled by the engine
/// that registers [WindowController.setWindowMethodHandler]. Auxiliary windows must
/// register on the child engine after [windowManager.ensureInitialized].
Future<void> registerDesktopAuxiliaryWindowControllerHandlers() async {
  try {
    final self = await WindowController.fromCurrentEngine();
    await self.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'window_close':
          try {
            await windowManager.close();
          } catch (e, st) {
            debugPrint('auxiliary window_close: $e\n$st');
          }
          return null;
        default:
          return null;
      }
    });
  } catch (e, st) {
    debugPrint('registerDesktopAuxiliaryWindowControllerHandlers: $e\n$st');
  }
}
