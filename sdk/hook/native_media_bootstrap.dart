import 'dart:io';

import 'package:path/path.dart' as p;

import 'matrix_native_media_env.dart';
import 'pdfium_hook_shared.dart';

/// Ensures `.matrix-sdk/native/` under [packageRoot] contains Pdfium (downloaded)
/// and optionally a host `ffmpeg` binary (copied from PATH / common locations).
///
/// Called from [hook/build.dart] so paths match [matrixNativeMediaCargoEnv].
Future<void> ensureMatrixNativeMediaArtifacts({
  required Uri packageRoot,
  void Function(String message)? log,
}) async {
  if (Platform.environment['MATRIX_HOOK_SKIP_NATIVE_MEDIA_BOOTSTRAP'] == '1') {
    log?.call(
      'matrix_sdk hook: MATRIX_HOOK_SKIP_NATIVE_MEDIA_BOOTSTRAP=1 — skip Pdfium/ffmpeg bootstrap',
    );
    return;
  }

  final root = Directory.fromUri(packageRoot);
  final nativeRoot = Directory(p.join(root.path, '.matrix-sdk', 'native'));
  await nativeRoot.create(recursive: true);
  try {
    await _ensurePdfiumHost(nativeRoot, packageRoot, log);
  } on Object catch (e) {
    log?.call('matrix_sdk hook: Pdfium setup failed (continuing): $e');
  }
  try {
    await _ensureFfmpegBinary(nativeRoot, log);
  } on Object catch (e) {
    log?.call('matrix_sdk hook: FFmpeg copy failed (continuing): $e');
  }
}

String? _hostPdfiumArchiveName() {
  if (Platform.isMacOS) {
    final r = Process.runSync('uname', ['-m']);
    final m = (r.stdout as String).trim();
    if (m == 'arm64') return 'pdfium-mac-arm64.tgz';
    return 'pdfium-mac-x64.tgz';
  }
  if (Platform.isLinux) {
    final r = Process.runSync('uname', ['-m']);
    final m = (r.stdout as String).trim();
    if (m == 'aarch64' || m == 'arm64') return 'pdfium-linux-arm64.tgz';
    return 'pdfium-linux-x64.tgz';
  }
  if (Platform.isWindows) {
    final a = (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '').toLowerCase();
    final w6432 =
        (Platform.environment['PROCESSOR_ARCHITEW6432'] ?? '').toLowerCase();
    if (a == 'arm64' || w6432 == 'arm64') return 'pdfium-win-arm64.tgz';
    return 'pdfium-win-x64.tgz';
  }
  return null;
}

bool _pdfiumPresentInLibDir(Directory libDir) {
  if (!libDir.existsSync()) return false;
  for (final e in libDir.listSync(followLinks: false)) {
    if (e is File && pdfiumLibBasename(p.basename(e.path))) return true;
  }
  return false;
}

Future<void> _ensurePdfiumHost(
  Directory nativeRoot,
  Uri packageRoot,
  void Function(String)? log,
) async {
  final pdfiumRoot = Directory(p.join(nativeRoot.path, 'pdfium'));
  final libDir = Directory(p.join(pdfiumRoot.path, 'lib'));
  await libDir.create(recursive: true);
  if (_pdfiumPresentInLibDir(libDir)) {
    log?.call('matrix_sdk hook: Pdfium already in .matrix-sdk/native/pdfium/lib');
    return;
  }

  final archiveName = _hostPdfiumArchiveName();
  if (archiveName == null) {
    log?.call('matrix_sdk hook: Pdfium: unsupported host OS');
    return;
  }

  final cacheDir = Directory(
    p.join(Directory.fromUri(packageRoot).path, '.matrix-sdk', 'cache'),
  );
  await cacheDir.create(recursive: true);
  final cacheTgz = File(p.join(cacheDir.path, archiveName));

  await pdfiumFetchExtractCopy(
    archiveName: archiveName,
    cacheTgz: cacheTgz,
    workRoot: pdfiumRoot,
    outLibDir: libDir,
    log: log,
  );
}

Future<void> _ensureFfmpegBinary(
  Directory nativeRoot,
  void Function(String)? log,
) async {
  final binDir = Directory(p.join(nativeRoot.path, 'bin'));
  await binDir.create(recursive: true);
  final name = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
  final dest = File(p.join(binDir.path, name));
  if (await dest.exists()) {
    final len = await dest.length();
    if (len > 10_000) {
      log?.call('matrix_sdk hook: FFmpeg already in .matrix-sdk/native/bin');
      return;
    }
  }

  final srcPath = matrixNativeMediaFfmpegCandidatePath();
  if (srcPath == null) {
    log?.call(
      'matrix_sdk hook: FFmpeg not found (install ffmpeg or set MATRIX_FFMPEG_PATH)',
    );
    return;
  }

  await File(srcPath).copy(dest.path);
  if (!Platform.isWindows) {
    await Process.run('chmod', ['+x', dest.path]);
  }
  log?.call('matrix_sdk hook: Copied ffmpeg from $srcPath');
}
