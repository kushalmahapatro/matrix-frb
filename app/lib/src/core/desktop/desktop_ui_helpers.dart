import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'desktop_esc_scope.dart';

/// macOS / Windows / Linux (not web, not mobile embedders).
bool isDesktopTargetPlatform() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;
}

/// Prefer centered dialog instead of a bottom sheet (desktop UX).
bool preferDialogOverModalSheet(BuildContext context) {
  if (!isDesktopTargetPlatform()) return false;
  final w = MediaQuery.sizeOf(context).width;
  return w >= 480;
}

/// Shows a bottom sheet on mobile/tablet and a dialog on desktop.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext sheetContext) builder,
  String? title,
  bool scrollControlled = false,
}) {
  if (preferDialogOverModalSheet(context)) {
    return showDialog<T>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: title != null
              ? Text(title, style: Theme.of(ctx).textTheme.titleLarge)
              : null,
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: DesktopEscScope(child: builder(ctx)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scrollControlled,
    showDragHandle: true,
    builder: builder,
  );
}

/// Dialog on desktop, bottom sheet on mobile — for full custom child (e.g. voice UI).
Future<T?> showAdaptivePanel<T>({
  required BuildContext context,
  required Widget Function(BuildContext sheetContext) builder,
  bool scrollControlled = false,
}) {
  if (preferDialogOverModalSheet(context)) {
    return showDialog<T>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
            ),
            child: DesktopEscScope(child: builder(ctx)),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scrollControlled,
    showDragHandle: true,
    builder: builder,
  );
}

/// Position for [showMenu] anchored near a global point (e.g. ⋮ button).
///
/// [anchorSize] should match the tap target so the menu opens beside the click.
RelativeRect desktopMenuPositionAt(
  BuildContext context,
  Offset globalTopLeft, {
  Size anchorSize = const Size(28, 28),
}) {
  final overlay =
      Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  final size = overlay?.size ?? MediaQuery.sizeOf(context);
  return RelativeRect.fromRect(
    Rect.fromLTWH(
      globalTopLeft.dx,
      globalTopLeft.dy,
      anchorSize.width,
      anchorSize.height,
    ),
    Offset.zero & size,
  );
}
