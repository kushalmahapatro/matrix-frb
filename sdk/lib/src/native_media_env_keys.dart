/// Environment variable names used by the Rust SDK for Pdfium and FFmpeg.
///
/// Match `matrix::native_media_env` in `sdk/rust`. For Flutter, pass values with
/// `--dart-define=PDFIUM_DYNAMIC_LIB_PATH=...` etc., or call [setNativeMediaEnv]
/// from `package:matrix_sdk/matrix_sdk.dart` with resolved paths at runtime.
///
/// **Bundled layout** (writable application support): `native_media/pdfium/`
/// (any file under it ⇒ Pdfium search dir) and `native_media/bin/ffmpeg`
/// (`ffmpeg.exe` on Windows) when that file exists.
abstract final class NativeMediaEnvKeys {
  NativeMediaEnvKeys._();

  /// Directory searched first for the Pdfium dynamic library.
  static const String pdfiumDynamicLibPath = 'PDFIUM_DYNAMIC_LIB_PATH';

  /// Additional directory containing the Pdfium shared library.
  static const String matrixPdfiumDir = 'MATRIX_PDFIUM_DIR';

  /// Full path to the `ffmpeg` executable when not on `PATH`.
  static const String matrixFfmpegPath = 'MATRIX_FFMPEG_PATH';
}
