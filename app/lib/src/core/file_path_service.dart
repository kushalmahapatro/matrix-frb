import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:matrix/src/core/native_media_platform_paths.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Application paths: database, logs, and optional native media (Pdfium / FFmpeg).
class FilePathService {
  static final FilePathService _instance = FilePathService._internal();
  factory FilePathService() => _instance;
  FilePathService._internal();

  /// Matrix [ClientConfig.sessionPath] and default location of Rust sidecar DB
  /// **`{path}/app/app_db.sqlite3`** (`file_upload_cache`: plain MXC + E2EE dedup by file hash).
  Future<String> getDatabasePath() async {
    if (kIsWeb || kIsWasm) {
      throw Exception('Database path is not supported on web and wasm');
    }

    if (Platform.isIOS) {
      final Directory dir = (await getApplicationDocumentsDirectory());
      return dir.path;
    }

    if (Platform.isAndroid) {
      final Directory dir = (await getApplicationSupportDirectory());
      final dbDir = Directory(join(dir.parent.path, 'database/s'));
      if (!(await dbDir.exists())) {
        await dbDir.create(recursive: true);
      }
      return dbDir.path;
    }

    if (Platform.isMacOS) {
      final Directory dir = (await getApplicationDocumentsDirectory());
      if (!(await dir.exists())) {
        await dir.create(recursive: true);
      }
      return dir.path;
    }

    if (Platform.isWindows) {
      // In Windows, the "TempPath" should be avoided because it's not in application specific area.
      final Directory dir = (await getApplicationSupportDirectory());
      final dbDir = Directory(join(dir.path, 'databases'));
      if (!(await dbDir.exists())) {
        await dbDir.create(recursive: true);
      }
      return dbDir.path;
    }

    if (Platform.isLinux) {
      final Directory dir = (await getApplicationSupportDirectory());
      final dbDir = Directory(join(dir.path, 'databases'));
      if (!(await dbDir.exists())) {
        await dbDir.create(recursive: true);
      }
      return dbDir.path;
    }

    throw Exception('Database path is not supported on this platform');
  }

  Future<String> getLogsPath() async {
    if (kIsWeb || kIsWasm) {
      throw Exception('Logs path is not supported on web and wasm');
    }

    final Directory dir = (await getApplicationCacheDirectory());
    return join(dir.path, 'logs');
  }

  /// Writable root for optional Pdfium / FFmpeg copies: `<applicationSupport>/native_media/`.
  Future<String> getNativeMediaRootPath() async {
    if (kIsWeb || kIsWasm) {
      throw Exception('Native media paths are not supported on web and wasm');
    }
    final Directory base = await getApplicationSupportDirectory();
    final root = join(base.path, 'native_media');
    await Directory(root).create(recursive: true);
    return root;
  }

  /// Directory Rust searches for Pdfium (`PDFIUM_DYNAMIC_LIB_PATH` / `MATRIX_PDFIUM_DIR`):
  /// `<applicationSupport>/native_media/pdfium/`.
  Future<String> getNativePdfiumDirectoryPath() async {
    final root = await getNativeMediaRootPath();
    final dir = join(root, 'pdfium');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// Copies Pdfium + ffmpeg from `matrix_sdk` Flutter assets (filled by `hook/build.dart`)
  /// into application support so Rust can dlopen / exec them.
  ///
  /// On Android, Pdfium is usually loaded from [NativeMediaPlatformPaths]; this is a fallback.
  /// FFmpeg is not materialized on iOS (no reliable subprocess binary in-tree).
  Future<void> materializeBundledNativeMediaFromAssets() async {
    if (kIsWeb || kIsWasm) return;

    final pdfNames = <String>[
      if (Platform.isIOS || Platform.isMacOS) 'libpdfium.dylib',
      if (Platform.isLinux || Platform.isAndroid) 'libpdfium.so',
      if (Platform.isWindows) 'pdfium.dll',
    ];
    final destPdfDir = await getNativePdfiumDirectoryPath();
    for (final n in pdfNames) {
      final key = 'packages/matrix_sdk/.matrix-sdk/native/pdfium/lib/$n';
      try {
        final data = await rootBundle.load(key);
        final out = File(join(destPdfDir, n));
        await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
        break;
      } on Object {
        continue;
      }
    }
  }
}
