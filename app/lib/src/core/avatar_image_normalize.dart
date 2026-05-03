import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Decodes raster images, applies EXIF orientation into pixels, then re-encodes
/// (JPEG for photos, PNG when the source was PNG so alpha is kept).
Uint8List? normalizeAvatarImageBytes(
  Uint8List raw,
  String path, {
  int jpegQuality = 88,
}) {
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return Uint8List.fromList(img.encodePng(oriented));
    }
    return Uint8List.fromList(
      img.encodeJpg(oriented, quality: jpegQuality),
    );
  } catch (_) {
    return null;
  }
}
