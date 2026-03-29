import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/src/core/file_path_service.dart';
import 'package:path/path.dart' as p;

/// Persists Matrix profile avatar thumbnails under the app media cache tree:
/// `{matrix_media_cache}/images/downloads/avatars/`, keyed by MXC URI (via SHA-256 of normalized URI).
class MatrixAvatarDiskCache {
  MatrixAvatarDiskCache._();
  static final MatrixAvatarDiskCache instance = MatrixAvatarDiskCache._();

  String? _dirPath;
  final Map<String, Future<Uint8List>> _inFlight = {};

  Future<String> _ensureDir() async {
    if (_dirPath != null) return _dirPath!;
    if (kIsWeb || kIsWasm) {
      throw UnsupportedError('Avatar disk cache is not supported on web');
    }
    final base = await FilePathService().getMatrixMediaCachePath();
    final dir = p.join(base, 'images', 'downloads', 'avatars');
    await Directory(dir).create(recursive: true);
    _dirPath = dir;
    return dir;
  }

  String _normalizedKey(String mxcUri) => mxcUri.trim().toLowerCase();

  /// Stable file name (hex SHA-256, filesystem-safe).
  String _fileNameForMxc(String mxcUri) {
    final digest = sha256.convert(utf8.encode(_normalizedKey(mxcUri)));
    return '$digest.avatar';
  }

  /// Returns cached bytes if the file exists and is non-empty.
  Future<Uint8List?> read(String mxcUri) async {
    if (kIsWeb || kIsWasm) return null;
    final t = mxcUri.trim();
    if (t.isEmpty) return null;
    try {
      final dir = await _ensureDir();
      final file = File(p.join(dir, _fileNameForMxc(t)));
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return bytes;
    } on Object {
      return null;
    }
  }

  /// Writes [bytes] for [mxcUri] atomically (temp file + rename).
  Future<void> write(String mxcUri, Uint8List bytes) async {
    if (kIsWeb || kIsWasm) return;
    final t = mxcUri.trim();
    if (t.isEmpty || bytes.isEmpty) return;
    try {
      final dir = await _ensureDir();
      final path = p.join(dir, _fileNameForMxc(t));
      final file = File(path);
      final tmp = File('$path.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
    } on Object {
      // Best-effort cache; ignore disk errors.
    }
  }

  /// Disk hit first; otherwise [download], then store and return. Coalesces concurrent downloads per URI.
  Future<Uint8List> loadOrFetch(
    String mxcUri,
    Future<Uint8List> Function() download,
  ) async {
    if (kIsWeb || kIsWasm) {
      return download();
    }
    final t = mxcUri.trim();
    if (t.isEmpty) {
      return download();
    }
    final cached = await read(t);
    if (cached != null) {
      return cached;
    }
    final key = _normalizedKey(t);
    final existing = _inFlight[key];
    if (existing != null) {
      return existing;
    }
    final fut = () async {
      try {
        final bytes = await download();
        if (bytes.isNotEmpty) {
          await write(t, bytes);
        }
        return bytes;
      } finally {
        _inFlight.remove(key);
      }
    }();
    _inFlight[key] = fut;
    return fut;
  }
}
