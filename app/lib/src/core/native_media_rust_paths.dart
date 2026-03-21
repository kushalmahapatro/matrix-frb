import 'package:matrix/src/core/domain/services/app_config.dart';

/// Paths passed to Rust [setNativeMediaEnv] (Pdfium dirs + `ffmpeg` binary).
class NativeMediaRustPaths {
  const NativeMediaRustPaths({
    this.pdfiumDynamicLibPath,
    this.matrixPdfiumDir,
    this.matrixFfmpegPath,
  });

  /// From `--dart-define` only (no filesystem fallbacks).
  factory NativeMediaRustPaths.fromDefinesOnly() {
    return NativeMediaRustPaths(
      pdfiumDynamicLibPath: _nonEmpty(AppConfig.nativePdfiumDynamicLibPath),
      matrixPdfiumDir: _nonEmpty(AppConfig.nativeMatrixPdfiumDir),
      matrixFfmpegPath: _nonEmpty(AppConfig.nativeMatrixFfmpegPath),
    );
  }

  final String? pdfiumDynamicLibPath;
  final String? matrixPdfiumDir;
  final String? matrixFfmpegPath;
}

String? _nonEmpty(String s) => s.isEmpty ? null : s;
