import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Application paths: database, logs, and Matrix media cache.
class FilePathService {
  static final FilePathService _instance = FilePathService._internal();
  factory FilePathService() => _instance;
  FilePathService._internal();

  /// Matrix [ClientConfig.sessionPath] and default location of Rust sidecar DB
  /// **`{path}/app/app_db.sqlite3`** (`file_upload_cache`: plain MXC + E2EE dedup by file hash).
  /// On Android this lives under `getApplicationSupportDirectory()/matrix_session/` (inside `files/`).
  Future<String> getDatabasePath() async {
    if (kIsWeb || kIsWasm) {
      throw Exception('Database path is not supported on web and wasm');
    }

    if (Platform.isIOS) {
      final Directory dir = (await getApplicationDocumentsDirectory());
      return dir.path;
    }

    if (Platform.isAndroid) {
      // [getApplicationSupportDirectory] is `Context.getFilesDir()` → `…/data/.../<pkg>/files`.
      // Do not use `dir.parent` here: that writes beside `files/` as `…/<pkg>/database/s`, which
      // is unusual and has been seen to break store creation on some release installs. Keep the
      // Matrix session under `files/` like other app-private data.
      final Directory dir = await getApplicationSupportDirectory();
      final dbDir = Directory(join(dir.path, 'matrix_session'));
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

  /// Decrypted timeline media cache root for Rust [ClientConfig.mediaCachePath]
  /// (`thumbnails/`, `media/full/`, …). Not stored as SQLite blobs.
  ///
  /// Dart-only profile avatars are stored under `images/downloads/avatars/` inside this root
  /// ([MatrixAvatarDiskCache]).
  Future<String> getMatrixMediaCachePath() async {
    if (kIsWeb || kIsWasm) {
      throw Exception('Matrix media cache path is not supported on web and wasm');
    }
    final Directory base = await getApplicationSupportDirectory();
    final String dir = join(base.path, 'matrix_media_cache');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  Future<String> getLogsPath() async {
    if (kIsWeb || kIsWasm) {
      throw Exception('Logs path is not supported on web and wasm');
    }

    final Directory dir = (await getApplicationCacheDirectory());
    final logsDir = Directory(join(dir.path, 'logs'));
    if (!(await logsDir.exists())) {
      await logsDir.create(recursive: true);
    }
    return logsDir.path;
  }

}
