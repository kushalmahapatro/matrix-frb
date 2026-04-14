import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_compact_call_window_size.dart';

/// Places the compact call popout inset from the bottom-right of the visible display.
Future<void> positionDesktopCompactCallWindowBottomRight({
  double margin = 12,
}) async {
  final size = DesktopCompactCallWindowSize.logicalSize;
  final base = await calcWindowPosition(size, Alignment.bottomRight);
  await windowManager.setPosition(
    Offset(base.dx - margin, base.dy - margin),
  );
}
