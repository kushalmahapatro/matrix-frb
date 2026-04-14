import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/src/core/calls/native_livekit_call_banner.dart';
import 'package:matrix/src/core/calls/native_livekit_call_host.dart';
import 'package:matrix/src/core/calls/native_livekit_call_session.dart';
import 'package:window_manager/window_manager.dart';

/// Child ongoing-call window invokes; **main** engine handles LiveKit session.
const WindowMethodChannel kDesktopOngoingCallChannel = WindowMethodChannel(
  'matrix_desktop/ongoing_call',
  mode: ChannelMode.unidirectional,
);

Future<void> registerDesktopOngoingCallMainBridge() async {
  await kDesktopOngoingCallChannel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'snapshot':
        return _snapshot();
      case 'toggleMicrophone':
        await _toggleMicrophone();
        return null;
      case 'toggleSpeaker':
        await _toggleSpeaker();
        return null;
      case 'toggleCamera':
        await _toggleCamera();
        return null;
      case 'hangUp':
        await _hangUp();
        return null;
      case 'focusMainWindow':
        await _focusMainWindow();
        return null;
      case 'openFullCallInMain':
        await _openFullCallInMain();
        return null;
      default:
        return null;
    }
  });
}

Map<String, dynamic> _snapshot() {
  final s = NativeLiveKitCallHost.instance.session;
  if (s == null ||
      s.phase == NativeLiveKitCallPhase.idle ||
      s.phase == NativeLiveKitCallPhase.ended) {
    return {'active': false};
  }
  final connecting = s.phase == NativeLiveKitCallPhase.connecting;
  final waiting = connecting || s.remoteParticipantCount <= 0;
  final durationOrStatus = connecting
      ? 'Connecting…'
      : (s.remoteParticipantCount <= 0
            ? 'Waiting for others…'
            : (s.connectedCallDurationLabel.isNotEmpty
                  ? s.connectedCallDurationLabel
                  : '0:00'));
  return {
    'active': true,
    'title': s.title,
    'durationOrStatus': durationOrStatus,
    'waiting': waiting,
    'connecting': connecting,
    'micMuted': s.micMuted,
    'speakerOn': s.speakerOn,
    'cameraMuted': s.cameraMuted,
    'voiceOnly': s.voiceOnly,
    'preferVideoCallUi': s.preferVideoCallUi,
    'remoteParticipantCount': s.remoteParticipantCount,
  };
}

Future<void> _toggleMicrophone() async {
  final s = NativeLiveKitCallHost.instance.session;
  if (s == null) return;
  await s.setMicrophoneMuted(!s.micMuted);
}

Future<void> _toggleSpeaker() async {
  final s = NativeLiveKitCallHost.instance.session;
  if (s == null) return;
  await s.setSpeakerOn(!s.speakerOn);
}

Future<void> _toggleCamera() async {
  final s = NativeLiveKitCallHost.instance.session;
  if (s == null) return;
  await s.setCameraMuted(!s.cameraMuted);
}

Future<void> _hangUp() async {
  final s = NativeLiveKitCallHost.instance.session;
  if (s == null) return;
  await s.hangUp();
}

Future<void> _focusMainWindow() async {
  try {
    await windowManager.ensureInitialized();
    await windowManager.focus();
  } catch (e, st) {
    debugPrint('DesktopOngoingCallMainBridge.focusMainWindow: $e\n$st');
  }
}

Future<void> _openFullCallInMain() async {
  await _focusMainWindow();
  // [markRouteVisible(true)] notifies [DesktopOngoingCallWindowAttacher] to close the popout.
  await openNativeLiveKitCallFullScreenRoute();
}
