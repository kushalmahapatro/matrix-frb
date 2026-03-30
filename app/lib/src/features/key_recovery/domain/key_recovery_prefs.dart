import 'package:shared_preferences/shared_preferences.dart';

/// Persists soft lockout after failed recovery passphrase attempts (login gate),
/// and “don’t show again” for the home key-recovery banner.
class KeyRecoveryPrefs {
  KeyRecoveryPrefs._();

  static const _softLockoutKey = 'key_recovery_soft_lockout';
  static const _bannerDontShowAgainKey = 'key_recovery_banner_dont_show_again';

  static Future<bool> isSoftLockout() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_softLockoutKey) ?? false;
  }

  static Future<void> setSoftLockout(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_softLockoutKey, value);
  }

  static Future<void> clearSoftLockout() async {
    await setSoftLockout(false);
  }

  /// User checked “Don’t show again” and dismissed or opened the recovery flow.
  static Future<bool> isBannerDontShowAgain() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_bannerDontShowAgainKey) ?? false;
  }

  static Future<void> setBannerDontShowAgain(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_bannerDontShowAgainKey, value);
  }

  /// Call on logout so the banner can appear again for the next account/session.
  static Future<void> clearBannerDontShowAgain() async {
    await setBannerDontShowAgain(false);
  }
}
