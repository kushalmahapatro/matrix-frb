import 'package:matrix_sdk/matrix_sdk.dart' show NativeMediaEnvKeys;

class AppConfig {
  // Environment configuration
  // static Uri homeserverUrl = Uri.parse('http://100.112.225.96:6167'); // mac mini synapse
  static Uri homeserverUrl = Uri.parse(
    'https://tuwunel.inve.dev',
  ); // mac mini tuwunel

  static bool proxyEnabled = bool.fromEnvironment('PROXY');

  static String proxyUrl = 'http://10.44.1.85:9090';

  static String? get registrationToken =>
      'WWwFFNPuKQyuAT2PNvji2Xd7fCsezyQmUl7fR/hl3V0=';

  /// Pdfium search path for Rust ([NativeMediaEnvKeys.pdfiumDynamicLibPath]). Empty = unset.
  static String get nativePdfiumDynamicLibPath => const String.fromEnvironment(
        NativeMediaEnvKeys.pdfiumDynamicLibPath,
        defaultValue: '',
      );

  /// Extra Pdfium directory for Rust ([NativeMediaEnvKeys.matrixPdfiumDir]). Empty = unset.
  static String get nativeMatrixPdfiumDir => const String.fromEnvironment(
        NativeMediaEnvKeys.matrixPdfiumDir,
        defaultValue: '',
      );

  /// `ffmpeg` binary path for Rust ([NativeMediaEnvKeys.matrixFfmpegPath]). Empty = unset.
  static String get nativeMatrixFfmpegPath => const String.fromEnvironment(
        NativeMediaEnvKeys.matrixFfmpegPath,
        defaultValue: '',
      );
}
