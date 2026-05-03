import 'dart:math' as math;
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

/// Decode params for timeline thumbnails so **aspect ratio is preserved**.
///
/// If both [Image.cacheWidth] and [Image.cacheHeight] are set, Flutter resizes
/// the decoded bitmap to that exact pixel size (non-uniform scale), which looks
/// stretched inside a fixed thumb frame even when [BoxFit.cover] is used.
({int? cacheWidth, int? cacheHeight}) timelineThumbImageDecodeCacheParams({
  required double logicalWidth,
  required double logicalHeight,
  BuildContext? context,
}) {
  final dpr = timelineThumbDevicePixelRatio(context);
  final wPx = (logicalWidth * dpr).round().clamp(1, 4096);
  final hPx = (logicalHeight * dpr).round().clamp(1, 4096);
  if (logicalWidth >= logicalHeight) {
    return (cacheWidth: wPx, cacheHeight: null);
  }
  return (cacheWidth: null, cacheHeight: hPx);
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

// --- Shared timeline / room-files thumbnail frame & raster preview meta ---

/// Default placeholder when event has no dimensions (message bubble media row).
const double kTimelineThumbPortraitW = 36;
const double kTimelineThumbPortraitH = 48;

/// Default wide placeholder (legacy bucket; prefer [timelineThumbBoxPreservingAspect]).
const double kTimelineThumbLandscapeW = 56;
const double kTimelineThumbLandscapeH = 32;

/// Longest logical edge for in-timeline raster thumbs (very small on-screen).
const double kTimelineThumbMaxLongEdgeLogical = 48;

/// JPEG / PNG decode size + EXIF orientation for layout and [exifQuarterTurns].
class RasterPreviewMeta {
  const RasterPreviewMeta(this.rawSize, this.exifOrientation);

  final Size rawSize;
  final int exifOrientation;
}

/// Decoder pixel size → logical size for layout (swap when EXIF implies 90° steps).
Size orientedIntrinsicForLayout(Size raw, int exifOrientation) {
  switch (exifOrientation) {
    case 5:
    case 6:
    case 7:
    case 8:
      return Size(raw.height, raw.width);
    default:
      return raw;
  }
}

/// [RotatedBox] quarter-turns (clockwise) to correct common EXIF orientations.
int exifQuarterTurns(int exifOrientation) {
  switch (exifOrientation) {
    case 3:
      return 2;
    case 6:
      return 1;
    case 8:
      return 3;
    default:
      return 0;
  }
}

/// Thumb frame from known pixel dimensions (e.g. event `info`); [exifOrientation] for JPEG layout.
Size timelineThumbFrameSizeForPixels(
  int w,
  int h, {
  int exifOrientation = 1,
}) {
  if (w > 0 && h > 0) {
    final oriented = orientedIntrinsicForLayout(
      Size(w.toDouble(), h.toDouble()),
      exifOrientation,
    );
    final portrait = oriented.height > oriented.width;
    return Size(
      portrait ? kTimelineThumbPortraitW : kTimelineThumbLandscapeW,
      portrait ? kTimelineThumbPortraitH : kTimelineThumbLandscapeH,
    );
  }
  return const Size(kTimelineThumbPortraitW, kTimelineThumbPortraitH);
}

Size timelineThumbFrameSizeFromPreviewMeta(RasterPreviewMeta meta) {
  return timelineThumbFrameSizeForPixels(
    meta.rawSize.width.round(),
    meta.rawSize.height.round(),
    exifOrientation: meta.exifOrientation,
  );
}

/// Preserves [oriented] aspect ratio; longest side is [maxLongEdgeLogical] (dp).
Size timelineThumbBoxPreservingAspect(
  Size oriented, {
  double maxLongEdgeLogical = kTimelineThumbMaxLongEdgeLogical,
}) {
  var w = oriented.width;
  var h = oriented.height;
  if (w <= 0 || h <= 0) {
    return const Size(kTimelineThumbPortraitW, kTimelineThumbPortraitH);
  }
  final long = math.max(w, h);
  final scale = maxLongEdgeLogical / long;
  return Size(w * scale, h * scale);
}

/// Uses event `info.w/h` (display dimensions) for blurhash / loading slot aspect.
Size timelineThumbBoxFromEventDimensions(int width, int height) {
  if (width <= 0 || height <= 0) {
    return const Size(kTimelineThumbPortraitW, kTimelineThumbPortraitH);
  }
  return timelineThumbBoxPreservingAspect(
    Size(width.toDouble(), height.toDouble()),
  );
}

bool _isJpegRasterBytes(Uint8List data) =>
    data.length >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF;

int _readUint16LeBe(Uint8List b, int offset, bool littleEndian) {
  final a = b[offset];
  final c = b[offset + 1];
  return littleEndian ? (a | (c << 8)) : ((a << 8) | c);
}

int _readUint32LeBe(Uint8List b, int offset, bool littleEndian) {
  if (littleEndian) {
    return b[offset] |
        (b[offset + 1] << 8) |
        (b[offset + 2] << 16) |
        (b[offset + 3] << 24);
  }
  return (b[offset] << 24) |
      (b[offset + 1] << 16) |
      (b[offset + 2] << 8) |
      b[offset + 3];
}

int? _readTiffOrientationIfd0(Uint8List b, int tiffStart, int tiffEnd) {
  if (tiffStart + 8 > tiffEnd) return null;
  final le = b[tiffStart] == 0x49 && b[tiffStart + 1] == 0x49;
  final be = b[tiffStart] == 0x4D && b[tiffStart + 1] == 0x4D;
  if (!le && !be) return null;
  final ifd0Off = _readUint32LeBe(b, tiffStart + 4, le);
  var ifd = tiffStart + ifd0Off;
  if (ifd < tiffStart || ifd + 2 > tiffEnd) return null;
  final n = _readUint16LeBe(b, ifd, le);
  var p = ifd + 2;
  for (var i = 0; i < n && p + 12 <= tiffEnd; i++) {
    final tag = _readUint16LeBe(b, p, le);
    final type = _readUint16LeBe(b, p + 2, le);
    final count = _readUint32LeBe(b, p + 4, le);
    if (tag == 0x0112 && type == 3) {
      if (count == 1) {
        return _readUint16LeBe(b, p + 8, le);
      }
      final vo = _readUint32LeBe(b, p + 8, le);
      final vp = tiffStart + vo;
      if (vp + 2 <= tiffEnd) {
        return _readUint16LeBe(b, vp, le);
      }
      return null;
    }
    p += 12;
  }
  return null;
}

int? _tryExifOrientationFromApp1(
  Uint8List b,
  int payloadStart,
  int payloadEnd,
) {
  if (payloadEnd - payloadStart < 6) return null;
  if (b[payloadStart] != 0x45 ||
      b[payloadStart + 1] != 0x78 ||
      b[payloadStart + 2] != 0x69 ||
      b[payloadStart + 3] != 0x66 ||
      b[payloadStart + 4] != 0 ||
      b[payloadStart + 5] != 0) {
    return null;
  }
  final tiffStart = payloadStart + 6;
  final o = _readTiffOrientationIfd0(b, tiffStart, payloadEnd);
  if (o == null || o < 1 || o > 8) return null;
  return o;
}

/// EXIF orientation 1–8 for JPEG; 1 if absent or not JPEG.
int _jpegExifOrientation(Uint8List b) {
  if (!_isJpegRasterBytes(b)) return 1;
  var i = 2;
  while (i + 3 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    if (marker == 0xD9) break;
    if (marker == 0xD8 || marker == 0x01) {
      i += 2;
      continue;
    }
    if (i + 4 > b.length) break;
    final segLen = _readUint16LeBe(b, i + 2, false);
    if (segLen < 2 || i + 2 + segLen > b.length) break;
    if (marker == 0xE1) {
      final payStart = i + 4;
      final payEnd = i + 2 + segLen;
      final o = _tryExifOrientationFromApp1(b, payStart, payEnd);
      if (o != null) return o;
    }
    i += 2 + segLen;
  }
  return 1;
}

/// Raw decoder size + JPEG EXIF orientation; `null` for unusably small decode.
Future<RasterPreviewMeta?> decodeRasterPreviewMeta(Uint8List data) async {
  if (data.isEmpty) return null;
  final exif = _jpegExifOrientation(data);
  ui.Codec? codec;
  try {
    final cap = kTimelineMetaDecodeMaxEdgePx;
    codec = await ui.instantiateImageCodec(data, targetWidth: cap);
    final frame = await codec.getNextFrame();
    final w = frame.image.width;
    final h = frame.image.height;
    frame.image.dispose();
    if (w < 1 || h < 1) return null;
    final longest = w > h ? w : h;
    // Allow small re-encoded timeline thumbs (long edge can be < 64 px).
    if (longest < 8) return null;
    return RasterPreviewMeta(Size(w.toDouble(), h.toDouble()), exif);
  } catch (_) {
    return null;
  } finally {
    codec?.dispose();
  }
}

/// Downscale to PNG for heap-friendly [Image.memory], preserving aspect (one codec dimension).
Future<Uint8List?> encodeRasterPngMaxLongEdgeWithMeta(
  Uint8List bytes,
  int maxLongEdgePx,
  RasterPreviewMeta meta,
) async {
  if (bytes.isEmpty || maxLongEdgePx < 1) return null;
  final o = orientedIntrinsicForLayout(meta.rawSize, meta.exifOrientation);
  final landscapeish = o.width >= o.height;
  ui.Codec? codec;
  try {
    codec = landscapeish
        ? await ui.instantiateImageCodec(bytes, targetWidth: maxLongEdgePx)
        : await ui.instantiateImageCodec(bytes, targetHeight: maxLongEdgePx);
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
