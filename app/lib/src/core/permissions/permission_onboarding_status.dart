import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/permissions/ios_matrix_microphone_channel.dart';
import 'package:permission_handler/permission_handler.dart';

/// Tri-state used by the permission onboarding cards and gate.
enum OnboardingPermissionStatus {
  granted,
  denied,
  notDetermined,
}

/// Resolves notifications, microphone, and camera for onboarding UI and skip logic.
class PermissionOnboardingStatuses {
  PermissionOnboardingStatuses._();

  static Future<OnboardingPermissionStatus> notification() async {
    if (kIsWeb) return OnboardingPermissionStatus.granted;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _fromPermissionStatus(await Permission.notification.status);
    }
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      try {
        final s = await FirebaseMessaging.instance.getNotificationSettings();
        switch (s.authorizationStatus) {
          case AuthorizationStatus.authorized:
          case AuthorizationStatus.provisional:
            return OnboardingPermissionStatus.granted;
          case AuthorizationStatus.denied:
            return OnboardingPermissionStatus.denied;
          case AuthorizationStatus.notDetermined:
            return OnboardingPermissionStatus.notDetermined;
        }
      } catch (_) {
        return OnboardingPermissionStatus.notDetermined;
      }
    }
    return OnboardingPermissionStatus.granted;
  }

  static Future<OnboardingPermissionStatus> microphone() async {
    if (kIsWeb) return OnboardingPermissionStatus.granted;
    // permission_handler has no macOS/Windows/Linux implementation for these
    // channels — calling it throws MissingPluginException.
    if (isDesktopTargetPlatform()) {
      return OnboardingPermissionStatus.granted;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final s = await iosRecordPermissionStatus();
      switch (s) {
        case 'granted':
          return OnboardingPermissionStatus.granted;
        case 'denied':
          return OnboardingPermissionStatus.denied;
        case 'undetermined':
          return OnboardingPermissionStatus.notDetermined;
        default:
          return _fromPermissionStatus(await Permission.microphone.status);
      }
    }
    return _fromPermissionStatus(await Permission.microphone.status);
  }

  static Future<OnboardingPermissionStatus> camera() async {
    if (kIsWeb) return OnboardingPermissionStatus.granted;
    if (isDesktopTargetPlatform()) {
      return OnboardingPermissionStatus.granted;
    }
    return _fromPermissionStatus(await Permission.camera.status);
  }

  /// All three are granted — onboarding screen can be skipped.
  static Future<bool> allRequiredGranted() async {
    if (kIsWeb) return true;
    final n = await notification();
    final m = await microphone();
    final c = await camera();
    return n == OnboardingPermissionStatus.granted &&
        m == OnboardingPermissionStatus.granted &&
        c == OnboardingPermissionStatus.granted;
  }

  static OnboardingPermissionStatus _fromPermissionStatus(PermissionStatus p) {
    if (p.isGranted) return OnboardingPermissionStatus.granted;
    if (p.isDenied || p.isPermanentlyDenied || p.isRestricted) {
      return OnboardingPermissionStatus.denied;
    }
    return OnboardingPermissionStatus.notDetermined;
  }
}
