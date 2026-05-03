import 'package:flutter/widgets.dart';

/// Updated by [LifeCycleAwareWidget] for notification foreground suppression.
class MatrixAppLifecycle {
  static AppLifecycleState state = AppLifecycleState.resumed;

  static bool get isForeground => state == AppLifecycleState.resumed;

  /// Treats [inactive] as in-app (system sheet / brief transitions) so message pushes
  /// are still suppressed while a conversation is open.
  static bool get isInteractiveLifecycle {
    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        return true;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        return false;
    }
  }
}
