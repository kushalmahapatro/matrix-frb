import 'package:flutter/widgets.dart';

import 'app_layout_variant.dart';

/// Read-only layout hint for thin UI (density, spacing). Policy stays in WM.
class AppLayoutScope extends InheritedWidget {
  const AppLayoutScope({
    super.key,
    required this.variant,
    required super.child,
  });

  final AppLayoutVariant variant;

  static AppLayoutVariant of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppLayoutScope>();
    assert(scope != null, 'AppLayoutScope not found');
    return scope!.variant;
  }

  static AppLayoutVariant? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppLayoutScope>()?.variant;
  }

  @override
  bool updateShouldNotify(AppLayoutScope oldWidget) =>
      oldWidget.variant != variant;
}
