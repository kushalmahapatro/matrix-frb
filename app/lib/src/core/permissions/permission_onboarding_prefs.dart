import 'package:shared_preferences/shared_preferences.dart';

/// Whether the user finished the post-auth permission onboarding flow.
class PermissionOnboardingPrefs {
  PermissionOnboardingPrefs._();

  static const _key = 'permission_onboarding_completed';

  static Future<bool> isCompleted() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_key) ?? false;
  }

  static Future<void> setCompleted() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, true);
  }

  /// Next login should show onboarding again for the new session.
  static Future<void> clearForLogout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
