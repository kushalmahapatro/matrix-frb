import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/state_management/base_state_widget_model.dart';
import 'package:matrix/src/features/auth/domain/models/auth_state.dart';
import 'package:matrix/src/features/auth/domain/services/auth_service.dart';
import 'package:matrix/src/features/auth/presentation/screens/login_screen.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix/src/rust/matrix/sync_service.dart' as sync;
import 'package:result_dart/result_dart.dart';

class LoginScreenModel extends ElementaryModel {
  LoginScreenModel(this._authService) : super();

  final AuthService _authService;

  Future<Result<bool>> login({
    required String username,
    required String password,
  }) async {
    return await _authService.login(username: username, password: password);
  }

  Future<Result<bool>> register({
    required String username,
    required String password,
  }) async {
    return await _authService.register(username: username, password: password);
  }

  Future<void> startSync() async {
    await sync.startSyncService();
  }
}

class LoginScreenWM extends BaseWidgetModel<LoginScreen, LoginScreenModel> {
  LoginScreenWM(super.model);
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

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
  ValueNotifier<AuthState> get authState => _authState;
  ValueNotifier<LoginFormData> get formData => _formData;

  @override
  void initWidgetModel() {
    super.initWidgetModel();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
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
      message:
          isRegistration ? 'CREATING ACCOUNT...' : 'CONNECTING TO MATRIX...',
    );

    try {
      final result =
          isRegistration
              ? await model.register(username: username, password: password)
              : await model.login(username: username, password: password);

      result.fold(
        (success) {
          model.startSync();
          _authState.value = const AuthState.authenticated();
          widget.navigateToChatListingScreen(context);
        },
        (failure) {
          _authState.value = AuthState.error(
            message: 'AUTHENTICATION FAILED. CHECK CREDENTIALS.',
          );
          LoggingService.error(
            'LOGIN_SCREEN',
            'Authentication failed: ${failure.toString()}',
          );
        },
      );
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
}
