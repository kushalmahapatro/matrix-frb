import 'package:matrix/src/rust/matrix/authentication.dart' as auth;
import 'package:result_dart/result_dart.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  Future<Result<bool>> login({
    required String username,
    required String password,
  }) async {
    try {
      final result = await auth.login(username: username, password: password);
      return Success(result);
    } catch (e) {
      return Failure(Exception('Login failed: $e'));
    }
  }

  Future<Result<bool>> register({
    required String username,
    required String password,
  }) async {
    try {
      final result = await auth.register(
        username: username,
        password: password,
      );
      return Success(result);
    } catch (e) {
      return Failure(Exception('Registration failed: $e'));
    }
  }

  Future<void> logout() async {
    await auth.logout();
  }
}
