import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/permissions/ios_matrix_microphone_channel.dart';
import 'package:permission_handler/permission_handler.dart';

/// Runtime checks for mic/camera with rationale dialogs and settings deep-link.
class AppRuntimePermissions {
  AppRuntimePermissions._();

  static bool get _isIos =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<bool> ensureMicrophone(
    BuildContext context, {
    required String title,
    required String rationale,
  }) async {
    if (kIsWeb) return false;

    // iOS: use AVAudioSession (Runner host) so the system prompt and Settings →
    // Privacy & Security → Microphone stay in sync for voice/calls.
    if (_isIos) {
      final nativeStatus = await iosRecordPermissionStatus();
      if (nativeStatus == 'granted') return true;
      if (nativeStatus == 'denied') {
        if (!context.mounted) return false;
        await _showRationaleDialog(
          context,
          title: title,
          message: rationale,
          showOpenSettings: true,
        );
        return false;
      }
      if (nativeStatus == 'undetermined') {
        final granted = await iosRequestRecordPermission();
        if (granted == true) return true;
        if (!context.mounted) return false;
        await _showRationaleDialog(
          context,
          title: title,
          message: rationale,
          showOpenSettings: granted == false,
        );
        return false;
      }
    }

    // permission_handler has no desktop implementation — throws MissingPluginException.
    if (isDesktopTargetPlatform()) {
      return true;
    }

    var status = await Permission.microphone.status;
    if (status.isGranted) return true;
    status = await Permission.microphone.request();
    if (status.isGranted) return true;
    if (!context.mounted) return false;
    await _showRationaleDialog(
      context,
      title: title,
      message: rationale,
      showOpenSettings: status.isPermanentlyDenied || status.isDenied,
    );
    return false;
  }

  static Future<bool> ensureCamera(
    BuildContext context, {
    required String title,
    required String rationale,
  }) async {
    if (kIsWeb) return false;
    if (isDesktopTargetPlatform()) {
      return true;
    }
    var status = await Permission.camera.status;
    if (status.isGranted) return true;
    status = await Permission.camera.request();
    if (status.isGranted) return true;
    if (!context.mounted) return false;
    await _showRationaleDialog(
      context,
      title: title,
      message: rationale,
      showOpenSettings: status.isPermanentlyDenied || status.isDenied,
    );
    return false;
  }

  static Future<bool> ensureMicrophoneForVoiceMessage(BuildContext context) {
    return ensureMicrophone(
      context,
      title: 'Microphone',
      rationale:
          'Voice messages are recorded from your microphone. You can enable '
          'access in Settings if you previously declined.',
    );
  }

  static Future<bool> ensureMicrophoneForVoiceCall(BuildContext context) {
    return ensureMicrophone(
      context,
      title: 'Microphone required',
      rationale:
          'Voice calls need the microphone so others can hear you. Enable it '
          'in Settings if you turned it off.',
    );
  }

  static Future<bool> ensureCameraAndMicForVideoCall(
    BuildContext context,
  ) async {
    final micOk = await ensureMicrophone(
      context,
      title: 'Microphone required',
      rationale:
          'Video calls need the microphone so others can hear you. Enable it '
          'in Settings if you turned it off.',
    );
    if (!micOk) return false;
    if (!context.mounted) return false;
    return ensureCamera(
      context,
      title: 'Camera required',
      rationale:
          'Video calls need the camera so others can see you. Enable it in '
          'Settings if you turned it off.',
    );
  }

  static Future<void> _showRationaleDialog(
    BuildContext context, {
    required String title,
    required String message,
    required bool showOpenSettings,
  }) async {
    final iosHint = _isIos
        ? '\n\nOn iPhone: Settings → Privacy & Security → Microphone → Matrix.'
        : '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text('$message$iosHint'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
          if (showOpenSettings)
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await openAppSettings();
              },
              child: const Text('Open settings'),
            ),
        ],
      ),
    );
  }
}
