import 'dart:async';

import 'package:elementary/elementary.dart';
import 'package:matrix/src/core/calls/call_history_store.dart';
import 'package:matrix/src/core/domain/services/app_config.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix/src/core/file_path_service.dart';
import 'package:matrix/src/core/state_management/base_state_widget_model.dart';
import 'package:matrix/src/features/settings/domain/profile_prefs.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/features/splash/presentation/screen/splash_screen.dart';
import 'package:result_dart/result_dart.dart';

class SplashScreenModel extends ElementaryModel {
  SplashScreenModel(this._matrixService, this._filePathService);
  final MatrixService _matrixService;
  final FilePathService _filePathService;

  Future<Result<bool>> initialize() async {
    return await _matrixService.initialize(
      dbPath: await _filePathService.getDatabasePath(),
      logsPath: await _filePathService.getLogsPath(),
      mediaCachePath: await _filePathService.getMatrixMediaCachePath(),
      showHomeServerForUsername: AppConfig.showHomeServerForUsername,
    );
  }

  Future<Result<bool>> isUserLoggedIn() async {
    return await _matrixService.isUserLoggedIn();
  }

  Future<void> startSync() async {
    await _matrixService.client.startSyncService();
  }
}

class SplashScreenWM extends BaseWidgetModel<SplashScreen, SplashScreenModel> {
  SplashScreenWM(super.model);

  Future<void> _startSyncInBackground() async {
    try {
      await model.startSync();
    } catch (e) {
      LoggingService.info(
        'SplashScreen',
        'startSync failed (will retry when online): $e',
      );
    }
  }

  @override
  void initWidgetModel() {
    _init();

    super.initWidgetModel();
  }

  void _init() async {
    final initSuccess = await model.initialize();
    initSuccess.fold(
      (success) => _checkIfUserLoggedIn(),
      (failure) => widget.navigateToErrorScreen(context, failure),
    );
  }

  Future<void> _checkIfUserLoggedIn() async {
    final userLoggedIn = await model.isUserLoggedIn();
    userLoggedIn.fold((success) async {
      if (success) {
        // Do not block the transition on sync — it can wait for network and
        // makes splash → home feel hung. Sync continues in the background.
        unawaited(_startSyncInBackground());
        unawaited(ProfilePrefs.instance.refresh(MatrixService().client));
        unawaited(CallHistoryStore.instance.ensureLoaded());
        if (context.mounted) {
          widget.navigateToChatScreen(context);
        }
      } else {
        widget.navigateToLoginScreen(context);
      }
    }, (failure) => widget.navigateToErrorScreen(context, failure));
  }
}
