import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:matrix_sdk/matrix_sdk.dart';

/// Shows the system incoming-call surface (CallKit on iOS, full-screen incoming UI on Android).
Future<void> showMatrixIncomingCallKit({
  required String callKitId,
  required SyncNotificationSummary s,
}) async {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  if (s.kind != SyncNotificationKind.incomingCall) return;

  final roomName = s.roomDisplayName ?? s.roomId;
  final caller = s.senderDisplayName?.isNotEmpty == true
      ? s.senderDisplayName!
      : s.senderId;

  final params = CallKitParams(
    id: callKitId,
    nameCaller: caller,
    appName: 'Matrix',
    handle: roomName,
    type: 0,
    duration: 30000,
    textAccept: 'Accept',
    textDecline: 'Decline',
    extra: <String, dynamic>{
      'roomId': s.roomId,
      'rtcEventId': s.eventId,
      'roomName': roomName,
    },
    android: const AndroidParams(
      isCustomNotification: true,
      isImportant: true,
      isShowFullLockedScreen: true,
      ringtonePath: 'system_ringtone_default',
      incomingCallNotificationChannelName: 'Incoming calls',
      missedCallNotificationChannelName: 'Missed calls',
    ),
    ios: const IOSParams(
      handleType: 'generic',
      supportsVideo: false,
      audioSessionActive: true,
      ringtonePath: 'system_ringtone_default',
    ),
  );

  try {
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  } catch (e, st) {
    debugPrint('showMatrixIncomingCallKit: $e\n$st');
  }
}
