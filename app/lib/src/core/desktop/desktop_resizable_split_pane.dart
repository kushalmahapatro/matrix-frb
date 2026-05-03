import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/src/core/desktop/desktop_sidebar_width_store.dart';

/// Master–detail row with a draggable vertical splitter (desktop-style).
class DesktopResizableSplitPane extends StatefulWidget {
  const DesktopResizableSplitPane({
    super.key,
    required this.sidebar,
    required this.detail,
    this.dividerColor,
  });

  final Widget sidebar;
  final Widget detail;
  final Color? dividerColor;

  @override
  State<DesktopResizableSplitPane> createState() =>
      _DesktopResizableSplitPaneState();
}

class _DesktopResizableSplitPaneState extends State<DesktopResizableSplitPane> {
  late double _sidebarWidth;

  @override
  void initState() {
    super.initState();
    _sidebarWidth = kDesktopSidebarWidthDefault;
    unawaited(_hydrateWidth());
  }

  Future<void> _hydrateWidth() async {
    final w = await loadDesktopSidebarWidth();
    if (mounted) setState(() => _sidebarWidth = w);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lineColor =
        widget.dividerColor ?? scheme.outlineVariant.withValues(alpha: 0.55);

    return Row(
      children: [
        SizedBox(
          width: _sidebarWidth,
          child: widget.sidebar,
        ),
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: Tooltip(
            message: 'Drag to resize room list',
            waitDuration: const Duration(milliseconds: 400),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _sidebarWidth = clampDesktopSidebarWidth(
                    _sidebarWidth + details.delta.dx,
                  );
                });
              },
              onHorizontalDragEnd: (_) {
                unawaited(saveDesktopSidebarWidth(_sidebarWidth));
              },
              child: SizedBox(
                width: 6,
                child: Center(
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: lineColor,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: widget.detail),
      ],
    );
  }
}
