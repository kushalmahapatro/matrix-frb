import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// True while Android cold-started for an incoming call accept (thin bootstrap).
///
/// When the call ends, [finishCallOnlyAndroidTask] runs so the user returns to the previous app.
final class AndroidCallOnlyMode {
  AndroidCallOnlyMode._();

  static bool _active = false;

  static bool get isActive => !kIsWeb && Platform.isAndroid && _active;

  static void markActive() {
    if (!kIsWeb && Platform.isAndroid) {
      _active = true;
    }
  }

  static void markInactive() {
    _active = false;
  }
}

/// Phase 2 (native Android, separate milestone): Telecom [ConnectionService] for system call UX,
/// explicit [foregroundServiceType] microphone/camera on API 34+, Picture-in-Picture for in-call UI,
/// and OEM-specific full-screen intent policies. Current stack uses [flutter_callkit_incoming] FGS.
final class AndroidCallSystemParityPhase2 {
  AndroidCallSystemParityPhase2._();
}

/// Reads CallKit accept payload placed on [MainActivity] by [flutter_callkit_incoming]
/// ([TransparentActivity] → [AppUtils.getAppIntent]).
final class AndroidCallLaunch {
  AndroidCallLaunch._();

  static const MethodChannel _channel = MethodChannel(
    'dev.inve.matrixchat/app_launch',
  );

  /// Returns and clears a pending accept launch (from activity intent). Call once per process start.
  static Future<Map<String, dynamic>?> takePendingCallAcceptIfAny() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'takePendingCallAccept',
      );
      if (raw == null) return null;
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
      return null;
    } catch (e, st) {
      debugPrint('AndroidCallLaunch.takePendingCallAcceptIfAny: $e\n$st');
      return null;
    }
  }

  static Future<void> finishCallOnlyTask() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('finishCallOnlyTask');
    } catch (e, st) {
      debugPrint('AndroidCallLaunch.finishCallOnlyTask: $e\n$st');
    }
  }
}
