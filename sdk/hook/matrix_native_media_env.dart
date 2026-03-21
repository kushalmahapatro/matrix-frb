import 'dart:io';

import 'package:path/path.dart' as p;

/// Environment forwarded to `cargo` when the SDK native hook builds Rust.
///
/// When [packageRoot] is set (from [BuildInput.packageRoot]), also uses binaries
/// under `<packageRoot>/.matrix-sdk/native/` produced by [ensureMatrixNativeMediaArtifacts].
///
/// For a running Flutter app, use `setNativeMediaEnv` with paths from the app’s
/// file path service / `--dart-define` (see `native_media_rust_paths.dart`).
Map<String, String> matrixNativeMediaCargoEnv({Uri? packageRoot}) {
  final platform = Platform.environment;
  final out = <String, String>{};

  var pdfiumLibDir = _nonEmpty(platform['PDFIUM_DYNAMIC_LIB_PATH']) ??
      _nonEmpty(platform['MATRIX_PDFIUM_DIR']);

  if (pdfiumLibDir == null) {
    final home = platform['HOME'] ?? platform['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      final d = '$home/.matrix-sdk/native/pdfium/lib';
      if (Directory(d).existsSync()) {
        pdfiumLibDir = d;
      }
    }
  }

  if (pdfiumLibDir == null && packageRoot != null) {
    final embedded = p.join(
      Directory.fromUri(packageRoot).path,
      '.matrix-sdk',
      'native',
      'pdfium',
      'lib',
    );
    if (_pdfiumLibDirHasLibrary(Directory(embedded))) {
      pdfiumLibDir = embedded;
    }
  }

  final pdfDirFinal = pdfiumLibDir;
  if (pdfDirFinal != null) {
    out['PDFIUM_DYNAMIC_LIB_PATH'] = pdfDirFinal;
    out['MATRIX_PDFIUM_DIR'] = pdfDirFinal;
  }

  var ffmpeg = _nonEmpty(platform['MATRIX_FFMPEG_PATH']);
  ffmpeg ??= matrixNativeMediaFfmpegCandidatePath();

  if (ffmpeg == null && packageRoot != null) {
    final name = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    final bundled = p.join(
      Directory.fromUri(packageRoot).path,
      '.matrix-sdk',
      'native',
      'bin',
      name,
    );
    if (File(bundled).existsSync()) {
      ffmpeg = bundled;
    }
  }

  final ffFinal = ffmpeg;
  if (ffFinal != null) {
    out['MATRIX_FFMPEG_PATH'] = ffFinal;
  }

  return out;
}

bool _pdfiumLibDirHasLibrary(Directory libDir) {
  if (!libDir.existsSync()) return false;
  for (final e in libDir.listSync(followLinks: false)) {
    if (e is! File) continue;
    final n = p.basename(e.path);
    if (n == 'libpdfium.dylib' ||
        n == 'libpdfium.so' ||
        n == 'pdfium.dll') {
      return true;
    }
  }
  return false;
}

String? _nonEmpty(String? s) {
  if (s == null) return null;
  final t = s.trim();
  return t.isEmpty ? null : t;
}

/// First existing `ffmpeg` binary from env / typical install paths (shared with bootstrap).
String? matrixNativeMediaFfmpegCandidatePath() {
  final fromEnv = _nonEmpty(Platform.environment['MATRIX_FFMPEG_PATH']);
  if (fromEnv != null && File(fromEnv).existsSync()) return fromEnv;
  return _firstExistingFile(matrixNativeMediaFfmpegCandidates());
}

String? _firstExistingFile(List<String> paths) {
  for (final path in paths) {
    try {
      if (File(path).existsSync()) return path;
    } on Object {
      continue;
    }
  }
  return null;
}

List<String> matrixNativeMediaFfmpegCandidates() {
  if (Platform.isMacOS) {
    return const [
      '/opt/homebrew/bin/ffmpeg',
      '/usr/local/bin/ffmpeg',
    ];
  }
  if (Platform.isLinux) {
    return const [
      '/usr/bin/ffmpeg',
      '/usr/local/bin/ffmpeg',
      '/snap/bin/ffmpeg',
    ];
  }
  if (Platform.isWindows) {
    final pf = Platform.environment['ProgramFiles'];
    final pf86 = Platform.environment['ProgramFiles(x86)'];
    return [
      if (pf != null) '$pf\\ffmpeg\\bin\\ffmpeg.exe',
      if (pf86 != null) '$pf86\\ffmpeg\\bin\\ffmpeg.exe',
      r'C:\ffmpeg\bin\ffmpeg.exe',
    ];
  }
  return const [];
}
