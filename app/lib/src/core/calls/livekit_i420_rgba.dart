import 'dart:typed_data';

/// Byte length of tightly packed I420 for [width]×[height] (full Y, then U, then V).
int expectedTightI420ByteLength(int width, int height) {
  final cw = (width + 1) >> 1;
  final ch = (height + 1) >> 1;
  return width * height + 2 * cw * ch;
}

/// BT.601 limited-range Y′CbCr to RGBA8888 (for [decodeImageFromPixels]).
Uint8List tightI420ToRgba8888(Uint8List i420, int width, int height) {
  final need = expectedTightI420ByteLength(width, height);
  if (width <= 0 || height <= 0 || i420.length < need) {
    return Uint8List(0);
  }
  final cw = (width + 1) >> 1;
  final ch = (height + 1) >> 1;
  final ySize = width * height;
  final out = Uint8List(width * height * 4);
  var o = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final yv = i420[y * width + x] & 0xff;
      final cx = x >> 1;
      final cy = y >> 1;
      final u = i420[ySize + cy * cw + cx] & 0xff;
      final v = i420[ySize + cw * ch + cy * cw + cx] & 0xff;
      final c = yv - 16;
      final d = u - 128;
      final e = v - 128;
      var r = (298 * c + 409 * e + 128) >> 8;
      var g = (298 * c - 100 * d - 208 * e + 128) >> 8;
      var b = (298 * c + 516 * d + 128) >> 8;
      if (r < 0) {
        r = 0;
      } else if (r > 255) {
        r = 255;
      }
      if (g < 0) {
        g = 0;
      } else if (g > 255) {
        g = 255;
      }
      if (b < 0) {
        b = 0;
      } else if (b > 255) {
        b = 255;
      }
      out[o++] = r;
      out[o++] = g;
      out[o++] = b;
      out[o++] = 255;
    }
  }
  return out;
}
