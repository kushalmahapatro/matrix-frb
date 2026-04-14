import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

/// Tightly packed I420: full Y plane, then U (½w×½h), then V (½w×½h).
///
/// Returns `null` if the [CameraImage] layout is not supported on this device.
Uint8List? tightI420FromCameraImage(CameraImage image) {
  if (image.format.group != ImageFormatGroup.yuv420) {
    return null;
  }

  final width = image.width;
  final height = image.height;
  final cw = width ~/ 2;
  final ch = height ~/ 2;
  final out = Uint8List(width * height + 2 * cw * ch);

  if (image.planes.length == 2 &&
      defaultTargetPlatform == TargetPlatform.iOS) {
    return _nv12LikeToI420(image, out, width, height, cw, ch);
  }

  if (image.planes.length == 3) {
    return _yuv420888LikeToI420(image, out, width, height, cw, ch);
  }

  return null;
}

Uint8List? _nv12LikeToI420(
  CameraImage image,
  Uint8List out,
  int width,
  int height,
  int cw,
  int ch,
) {
  final yPlane = image.planes[0];
  final uvPlane = image.planes[1];
  final yRow = yPlane.bytesPerRow;
  final uvRow = uvPlane.bytesPerRow;

  var pos = 0;
  for (var row = 0; row < height; row++) {
    final src = row * yRow;
    out.setRange(pos, pos + width, yPlane.bytes, src);
    pos += width;
  }

  for (var row = 0; row < ch; row++) {
    for (var col = 0; col < cw; col++) {
      final ix = row * uvRow + col * 2;
      if (ix + 1 >= uvPlane.bytes.length) return null;
      out[pos++] = uvPlane.bytes[ix];
    }
  }
  for (var row = 0; row < ch; row++) {
    for (var col = 0; col < cw; col++) {
      final ix = row * uvRow + col * 2;
      out[pos++] = uvPlane.bytes[ix + 1];
    }
  }
  return out;
}

Uint8List? _yuv420888LikeToI420(
  CameraImage image,
  Uint8List out,
  int width,
  int height,
  int cw,
  int ch,
) {
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final yRow = yPlane.bytesPerRow;
  final uRow = uPlane.bytesPerRow;
  final vRow = vPlane.bytesPerRow;
  final uPix = uPlane.bytesPerPixel ?? 1;
  final vPix = vPlane.bytesPerPixel ?? 1;

  var pos = 0;
  for (var row = 0; row < height; row++) {
    final src = row * yRow;
    out.setRange(pos, pos + width, yPlane.bytes, src);
    pos += width;
  }

  for (var row = 0; row < ch; row++) {
    for (var col = 0; col < cw; col++) {
      final ix = row * uRow + col * uPix;
      if (ix >= uPlane.bytes.length) return null;
      out[pos++] = uPlane.bytes[ix];
    }
  }
  for (var row = 0; row < ch; row++) {
    for (var col = 0; col < cw; col++) {
      final ix = row * vRow + col * vPix;
      if (ix >= vPlane.bytes.length) return null;
      out[pos++] = vPlane.bytes[ix];
    }
  }
  return out;
}
