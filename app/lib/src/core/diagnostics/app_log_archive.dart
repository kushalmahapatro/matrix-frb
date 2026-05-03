import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/src/core/file_path_service.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Builds a ZIP of the Rust rolling-file log directory (same path as [TracingFileConfiguration.path]).
class AppLogArchive {
  AppLogArchive._();

  static Future<String> _logsDirectory() async {
    final configured = MatrixService().rustRollingLogsDirectory;
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }
    return FilePathService().getLogsPath();
  }

  /// Creates `matrix-terminal-logs-*.zip` under the app temp directory.
  static Future<File> createZipInTemp() async {
    if (kIsWeb) {
      throw UnsupportedError('Log export is not supported on web.');
    }
    final dir = Directory(await _logsDirectory());
    if (!await dir.exists()) {
      throw StateError('Log directory does not exist: ${dir.path}');
    }
    final temp = await getTemporaryDirectory();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final outPath = p.join(temp.path, 'matrix-terminal-logs-$stamp.zip');
    await ZipFileEncoder().zipDirectory(dir, filename: outPath);
    return File(outPath);
  }
}
