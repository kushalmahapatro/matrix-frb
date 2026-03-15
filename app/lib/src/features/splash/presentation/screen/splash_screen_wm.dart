import 'dart:async';

import 'package:elementary/elementary.dart';
import 'package:matrix/src/core/file_path_service.dart';
import 'package:matrix/src/core/state_management/base_state_widget_model.dart';
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
    await Future.delayed(const Duration(seconds: 2));
    userLoggedIn.fold((success) async {
      if (success) {
        await model.startSync();
        if (context.mounted) {
          widget.navigateToChatScreen(context);
        }
      } else {
        widget.navigateToLoginScreen(context);
      }
    }, (failure) => widget.navigateToErrorScreen(context, failure));
  }
}
