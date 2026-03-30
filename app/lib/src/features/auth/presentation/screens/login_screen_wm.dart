import 'dart:async';

import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/domain/services/app_config.dart';
import 'package:matrix/src/core/state_management/base_state_widget_model.dart';
import 'package:matrix/src/features/auth/domain/models/auth_state.dart';

import 'package:matrix/src/features/settings/domain/profile_prefs.dart';
import 'package:matrix/src/features/auth/presentation/screens/login_screen.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/features/key_recovery/domain/key_recovery_prefs.dart';
import 'package:matrix/src/features/key_recovery/presentation/screens/login_recovery_unlock_screen.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:result_dart/result_dart.dart';

class LoginScreenModel extends ElementaryModel {
  LoginScreenModel(this._matrixService) : super();

  final MatrixService _matrixService;

  Future<Result<bool>> login({
    required String username,
    required String password,
  }) async {
    try {
      final result = await _matrixService.client.login(
        username: username,
        password: password,
      );
      return Success(result);
    } catch (e) {
      return Failure(Exception('Login failed: $e'));
    }
  }

  Future<Result<bool>> register({
    required String username,
    required String password,
    required String displayName,
  }) async {
    try {
      final result = await _matrixService.client.register(
        username: username,
        password: password,
        displayName: displayName,
        token: AppConfig.registrationToken,
      );
      return Success(result);
    } catch (e) {
      return Failure(Exception('Registration failed: $e'));
    }
  }

  Future<void> startSync() async {
    await _matrixService.client.startSyncService();
  }
}

class LoginScreenWM extends BaseWidgetModel<LoginScreen, LoginScreenModel> {
  LoginScreenWM(super.model);
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _displayNameController;

  final ValueNotifier<AuthState> _authState = ValueNotifier(
    const AuthState.initial(),
  );
  final ValueNotifier<LoginFormData> _formData = ValueNotifier(
    const LoginFormData(),
  );

  // Getters
  GlobalKey<FormState> get formKey => _formKey;
  TextEditingController get usernameController => _usernameController;
  TextEditingController get passwordController => _passwordController;
  TextEditingController get displayNameController => _displayNameController;
  ValueNotifier<AuthState> get authState => _authState;
  ValueNotifier<LoginFormData> get formData => _formData;

  @override
  void initWidgetModel() {
    super.initWidgetModel();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _displayNameController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _authState.dispose();
    _formData.dispose();
    super.dispose();
  }

  void toggleRegistration() {
    _formData.value = _formData.value.copyWith(
      isRegistration: !_formData.value.isRegistration,
    );
  }

  void togglePasswordVisibility() {
    _formData.value = _formData.value.copyWith(
      showPassword: !_formData.value.showPassword,
    );
  }

  Future<void> authenticate() async {
    if (!_formKey.currentState!.validate()) return;

    final isRegistration = _formData.value.isRegistration;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    _authState.value = AuthState.loading(
      message: isRegistration
          ? 'CREATING ACCOUNT...'
          : 'CONNECTING TO MATRIX...',
    );

    try {
      final result = isRegistration
          ? await model.register(
                username: username,
                password: password,
                displayName: _displayNameController.text.trim().isNotEmpty
                    ? _displayNameController.text.trim()
                    : username,
              )
          : await model.login(username: username, password: password);

      if (result.isSuccess() && result.getOrNull() == true) {
        await model.startSync();
        unawaited(ProfilePrefs.instance.refresh(MatrixService().client));
        await MatrixService().startMatrixNotificationsIfReady();
        if (!context.mounted) return;
        _authState.value = const AuthState.authenticated();

        if (isRegistration) {
          widget.navigateToPostRegistrationRecovery(context);
          return;
        }

        try {
          await MatrixService().client.refreshRecoveryState();
          final recoveryState = await MatrixService().client.getRecoveryState();
          if (!context.mounted) return;
          final lockedOut = await KeyRecoveryPrefs.isSoftLockout();
          if (!context.mounted) return;
          if (recoveryState == 'incomplete' && !lockedOut) {
            NavigatorService.pushReplacement(
              context,
              const LoginRecoveryUnlockScreen(),
            );
            return;
          }
        } catch (e) {
          LoggingService.error(
            'LOGIN_SCREEN',
            'Recovery state check failed: $e',
          );
        }

        if (!context.mounted) return;
        widget.navigateToChatListingScreen(context);
      } else {
        _authState.value = AuthState.error(
          message: 'AUTHENTICATION FAILED. CHECK CREDENTIALS.',
        );
        LoggingService.error(
          'LOGIN_SCREEN',
          'Authentication failed: ${result.exceptionOrNull()?.toString() ?? 'unknown'}',
        );
      }
    } catch (e) {
      _authState.value = AuthState.error(message: 'ERROR: $e');
      LoggingService.error('LOGIN_SCREEN', 'Unknown error: ${e.toString()}');
    }
  }

  String? validateUsername(String? value) {
    if (value == null || value.isEmpty) {
      return 'Username is required';
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    return null;
  }

  String? validateDisplayName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Display name is required';
    }
    return null;
  }
}
