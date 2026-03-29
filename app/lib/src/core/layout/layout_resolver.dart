import 'package:flutter/widgets.dart';

import 'app_layout_variant.dart';

import '../desktop/desktop_ui_helpers.dart';

/// Landscape → split; wide **desktop** windows → split even in “portrait”
/// (desktop often reports portrait while still being a large resizable window).
AppLayoutVariant resolveLayoutVariant(MediaQueryData mq) {
  if (mq.orientation == Orientation.landscape) {
    return AppLayoutVariant.split;
  }
  if (isDesktopTargetPlatform() && mq.size.width >= 720) {
    return AppLayoutVariant.split;
  }
  return AppLayoutVariant.compact;
}
