import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Upper bound for a first-pass decode when reading dimensions / aspect only.
const int kTimelineMetaDecodeMaxEdgePx = 512;

/// [MediaQuery.devicePixelRatio] when [context] is available; else the platform view.
double timelineThumbDevicePixelRatio([BuildContext? context]) {
  if (context != null) {
    final mq = MediaQuery.maybeOf(context);
    if (mq != null) return mq.devicePixelRatio;
  }
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return 1.0;
  return views.first.devicePixelRatio;
}

/// Physical pixel extent for one logical edge of a timeline thumbnail (clamped).
int timelineThumbDecodeExtentPx(double logicalExtent, [BuildContext? context]) {
  final v = (logicalExtent * timelineThumbDevicePixelRatio(context)).round();
  return v.clamp(1, 4096);
}

({int cacheWidth, int cacheHeight}) timelineImageCacheDimensions(
  BuildContext context, {
  required double logicalWidth,
  required double logicalHeight,
}) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  return (
    cacheWidth: (logicalWidth * dpr).round().clamp(1, 4096),
    cacheHeight: (logicalHeight * dpr).round().clamp(1, 4096),
  );
}

/// Decodes [bytes] to fit inside the box (aspect preserved) and returns small PNG
/// bytes for [Image.memory], cutting Dart heap vs holding a large server thumbnail.
Future<Uint8List?> encodeRasterPngFitBox(
  Uint8List bytes, {
  required int targetWidthPx,
  required int targetHeightPx,
}) async {
  if (bytes.isEmpty) return null;
  if (targetWidthPx < 1 || targetHeightPx < 1) return null;
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidthPx,
      targetHeight: targetHeightPx,
    );
    final frame = await codec.getNextFrame();
    final bd = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    return bd?.buffer.asUint8List();
  } catch (_) {
    return null;
  } finally {
    codec?.dispose();
  }
}
