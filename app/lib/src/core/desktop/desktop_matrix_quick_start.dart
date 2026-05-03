import 'package:matrix/src/core/domain/services/app_config.dart';
import 'package:matrix/src/core/file_path_service.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix_sdk/init.dart';
import 'package:media_kit/media_kit.dart';
import 'package:result_dart/result_dart.dart';

/// Rust + Matrix client for the current isolate (main app or a
/// [desktop_multi_window] secondary engine).
Future<Result<bool>> initMatrixDesktopIsolate() async {
  MediaKit.ensureInitialized();
  await MatrixSdk.init();
  final fps = FilePathService();
  return MatrixService().initialize(
    dbPath: await fps.getDatabasePath(),
    logsPath: await fps.getLogsPath(),
    mediaCachePath: await fps.getMatrixMediaCachePath(),
    showHomeServerForUsername: AppConfig.showHomeServerForUsername,
  );
}
