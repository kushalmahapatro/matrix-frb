import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class FilePathService {
  static final FilePathService _instance = FilePathService._internal();
  factory FilePathService() => _instance;
  FilePathService._internal();

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
      final dbDir = Directory(join(dir.parent.path, 'databases'));
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
}
