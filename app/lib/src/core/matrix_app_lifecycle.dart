import 'package:flutter/widgets.dart';

/// Updated by [LifeCycleAwareWidget] for notification foreground suppression.
class MatrixAppLifecycle {
  static AppLifecycleState state = AppLifecycleState.resumed;

  static bool get isForeground => state == AppLifecycleState.resumed;
}
