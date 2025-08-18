import 'dart:async';

import 'package:elementary/elementary.dart';
import 'package:matrix/src/core/state_management/base_state_widget_model.dart';
import 'package:matrix/src/features/splash/domain/services/initialization_service.dart';
import 'package:matrix/src/features/splash/presentation/screen/splash_screen.dart';
import 'package:matrix/src/rust/matrix/sync_service.dart' as sync;
import 'package:result_dart/result_dart.dart';

class SplashScreenModel extends ElementaryModel {
  SplashScreenModel(this._initializationService);
  final InitializationService _initializationService;

  Future<Result<bool>> initialize() async {
    return await _initializationService.initialize();
  }

  Future<Result<bool>> isUserLoggedIn() async {
    return await _initializationService.isUserLoggedIn();
  }

  Future<void> startSync() async {
    await sync.startSyncService();
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
