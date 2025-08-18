enum DataMode { mock, real }

class AppConfig {
  // Environment configuration
  static Uri homeserverUrl = Uri.parse('http://localhost:8008');

  // Test configuration
  static const String testUsername = 'test_user';
  static const String testPassword = 'test_password';
  static const Duration mockDelay = Duration(milliseconds: 500);
  static const Duration realTimeout = Duration(seconds: 30);
}
