import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_state.freezed.dart';

@freezed
abstract class AuthState with _$AuthState {
  const factory AuthState.initial() = AuthStateInitial;
  const factory AuthState.loading({required String message}) = AuthStateLoading;
  const factory AuthState.authenticated() = AuthStateAuthenticated;
  const factory AuthState.error({required String message}) = AuthStateError;
}

@freezed
abstract class LoginFormData with _$LoginFormData {
  const factory LoginFormData({
    @Default('') String username,
    @Default('') String password,
    @Default(false) bool isRegistration,
    @Default(false) bool showPassword,
  }) = _LoginFormData;
}
