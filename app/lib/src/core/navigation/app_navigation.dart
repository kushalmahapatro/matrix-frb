import 'package:flutter/material.dart';

/// Root [NavigatorState] for push from services (incoming call → Element Call).
class AppNavigation {
  AppNavigation._();

  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();
}
