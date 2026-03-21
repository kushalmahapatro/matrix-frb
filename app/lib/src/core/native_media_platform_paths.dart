import 'dart:io';

import 'package:flutter/services.dart';

/// Android: directory where Flutter/native assets place `.so` files (e.g. `libpdfium.so`).
class NativeMediaPlatformPaths {
  static const _channel = MethodChannel('dev.inve.matrixchat/native_media');

  /// `ApplicationInfo.nativeLibraryDir` on Android; `null` elsewhere or if unavailable.
  static Future<String?> androidNativeLibraryDir() async {
    if (!Platform.isAndroid) return null;
    try {
      final dir = await _channel.invokeMethod<String>('getNativeLibraryDir');
      if (dir == null) return null;
      final t = dir.trim();
      return t.isEmpty ? null : t;
    } on Object {
      return null;
    }
  }
}
