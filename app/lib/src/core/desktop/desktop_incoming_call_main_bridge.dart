import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:matrix/src/core/calls/call_history_store.dart';
import 'package:matrix/src/core/calls/incoming_call_banner_controller.dart';
import 'package:matrix/src/core/calls/matrix_call_kit_coordinator.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';

/// Unidirectional channel: child incoming-call window invokes; **main** engine
/// registers the handler (see [registerDesktopIncomingCallMainBridge]).
const WindowMethodChannel kDesktopIncomingCallChannel = WindowMethodChannel(
  'matrix_desktop/incoming_call',
  mode: ChannelMode.unidirectional,
);

/// Call once from the **main** desktop engine (e.g. [main.dart] after routing).
Future<void> registerDesktopIncomingCallMainBridge() async {
  await kDesktopIncomingCallChannel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'incomingCallAccepted':
        return _onIncomingAccepted(call);
      case 'incomingCallDeclined':
        return _onIncomingDeclined(call);
      default:
        return;
    }
  });
}

Future<void> _onIncomingAccepted(MethodCall call) async {
  final m = call.arguments;
  if (m is! Map) return;
  final roomId = m['roomId']?.toString() ?? '';
  final roomName = m['roomName']?.toString() ?? '';
  final callKitId = m['callKitId']?.toString();

  IncomingCallBannerController.instance.dismiss();
  await MatrixCallKitCoordinator.instance.endCallKitIncomingIfStored(callKitId);

  if (!MatrixService().isInitialized) {
    debugPrint(
      'DesktopIncomingCallMainBridge: Matrix not initialized; cannot accept.',
    );
    return;
  }

  try {
    await MatrixCallKitCoordinator.instance.openAcceptedIncomingNativeLiveKit(
      client: MatrixService().client,
      roomId: roomId,
      roomName: roomName.isNotEmpty ? roomName : roomId,
    );
  } catch (e, st) {
    debugPrint('DesktopIncomingCallMainBridge accept: $e\n$st');
  }
}

Future<void> _onIncomingDeclined(MethodCall call) async {
  final m = call.arguments;
  if (m is! Map) return;
  final roomId = m['roomId']?.toString() ?? '';
  final rtcEventId = m['rtcEventId']?.toString() ?? '';
  final callKitId = m['callKitId']?.toString();
  final reason = m['reason']?.toString() ?? 'Declined';

  IncomingCallBannerController.instance.dismiss();
  await MatrixCallKitCoordinator.instance.endCallKitIncomingIfStored(callKitId);

  if (MatrixService().isInitialized &&
      roomId.isNotEmpty &&
      rtcEventId.isNotEmpty) {
    try {
      await MatrixService().client.declineRtcCall(
        roomId: roomId,
        rtcNotificationEventId: rtcEventId,
      );
    } catch (e, st) {
      debugPrint('DesktopIncomingCallMainBridge decline: $e\n$st');
    }
  }

  if (roomId.isNotEmpty) {
    unawaited(
      CallHistoryStore.instance.appendIncomingCallOutcome(
        roomId: roomId,
        roomName: m['roomName']?.toString() ?? roomId,
        isDirectRoom: false,
        voiceOnly: true,
        endReason: reason,
      ),
    );
  }
}
