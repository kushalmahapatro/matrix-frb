import 'dart:convert';

import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';

/// JSON payload in [WindowController.arguments] for [desktop_multi_window].
///
/// Main window uses an empty string; extra engines pass encoded JSON.
abstract final class DesktopWindowArgs {
  static const String typeKey = 't';
  static const String typeConversation = 'conversation';
  static const String typeIncomingCall = 'incoming_call';
  static const String typeOngoingCall = 'ongoing_call';

  /// True when this engine should run the normal app shell.
  static bool isMainWindow(String raw) {
    if (raw.trim().isEmpty) return true;
    final m = _tryDecode(raw);
    return m == null || m[typeKey] == null || m[typeKey] == 'main';
  }

  static Map<String, dynamic>? _tryDecode(String raw) {
    try {
      final v = jsonDecode(raw);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }

  /// Encodes a pop-out conversation window (second Flutter engine).
  static String encodeConversation({
    required String roomId,
    required String roomName,
    required ChatRoomStatus status,
    required bool isDarkMode,
  }) {
    return jsonEncode({
      typeKey: typeConversation,
      'roomId': roomId,
      'roomName': roomName,
      'status': status.name,
      'dark': isDarkMode,
    });
  }

  static DesktopConversationWindowArgs? tryParseConversation(String raw) {
    final m = _tryDecode(raw);
    if (m == null || m[typeKey] != typeConversation) return null;
    final roomId = m['roomId'] as String?;
    final roomName = m['roomName'] as String?;
    final statusName = m['status'] as String?;
    if (roomId == null || roomName == null || statusName == null) return null;
    ChatRoomStatus status = ChatRoomStatus.joined;
    for (final v in ChatRoomStatus.values) {
      if (v.name == statusName) {
        status = v;
        break;
      }
    }
    final dark = m['dark'] as bool? ?? true;
    return DesktopConversationWindowArgs(
      roomId: roomId,
      roomName: roomName,
      status: status,
      isDarkMode: dark,
    );
  }

  /// Second-engine incoming MatrixRTC ring (no Matrix init in child — UI + RPC only).
  static String encodeIncomingCall({
    required String roomId,
    required String rtcEventId,
    required String roomName,
    required String callerLabel,
    String? callKitId,
    required bool isDarkMode,
  }) {
    return jsonEncode({
      typeKey: typeIncomingCall,
      'roomId': roomId,
      'rtcEventId': rtcEventId,
      'roomName': roomName,
      'callerLabel': callerLabel,
      if (callKitId != null && callKitId.isNotEmpty) 'callKitId': callKitId,
      'dark': isDarkMode,
    });
  }

  static DesktopIncomingCallWindowArgs? tryParseIncomingCall(String raw) {
    final m = _tryDecode(raw);
    if (m == null || m[typeKey] != typeIncomingCall) return null;
    final roomId = m['roomId'] as String?;
    final rtcEventId = m['rtcEventId'] as String?;
    final roomName = m['roomName'] as String?;
    final callerLabel = m['callerLabel'] as String?;
    if (roomId == null ||
        rtcEventId == null ||
        roomName == null ||
        callerLabel == null) {
      return null;
    }
    final dark = m['dark'] as bool? ?? true;
    final ck = m['callKitId'] as String?;
    return DesktopIncomingCallWindowArgs(
      roomId: roomId,
      rtcEventId: rtcEventId,
      roomName: roomName,
      callerLabel: callerLabel,
      callKitId: ck,
      isDarkMode: dark,
    );
  }

  /// Second-engine ongoing call chrome (controls + status); LiveKit stays on main.
  static String encodeOngoingCall({
    required bool isDarkMode,
    required bool voiceOnly,
    required bool preferVideoCallUi,
    required String title,
    required String roomId,
    required String callInstanceId,
  }) {
    return jsonEncode({
      typeKey: typeOngoingCall,
      'dark': isDarkMode,
      'voiceOnly': voiceOnly,
      'preferVideoCallUi': preferVideoCallUi,
      'title': title,
      'roomId': roomId,
      'callInstanceId': callInstanceId,
    });
  }

  static DesktopOngoingCallWindowArgs? tryParseOngoingCall(String raw) {
    final m = _tryDecode(raw);
    if (m == null || m[typeKey] != typeOngoingCall) return null;
    final title = m['title'] as String?;
    if (title == null) return null;
    final dark = m['dark'] as bool? ?? true;
    final voiceOnly = m['voiceOnly'] as bool? ?? false;
    final preferVideo = m['preferVideoCallUi'] as bool? ?? false;
    final roomId = m['roomId'] as String? ?? '';
    final callInstanceId = m['callInstanceId'] as String? ?? '';
    return DesktopOngoingCallWindowArgs(
      title: title,
      isDarkMode: dark,
      voiceOnly: voiceOnly,
      preferVideoCallUi: preferVideo,
      roomId: roomId,
      callInstanceId: callInstanceId,
    );
  }
}

class DesktopConversationWindowArgs {
  const DesktopConversationWindowArgs({
    required this.roomId,
    required this.roomName,
    required this.status,
    required this.isDarkMode,
  });

  final String roomId;
  final String roomName;
  final ChatRoomStatus status;
  final bool isDarkMode;
}

class DesktopOngoingCallWindowArgs {
  const DesktopOngoingCallWindowArgs({
    required this.title,
    required this.isDarkMode,
    required this.voiceOnly,
    required this.preferVideoCallUi,
    required this.roomId,
    required this.callInstanceId,
  });

  final String title;
  final bool isDarkMode;
  final bool voiceOnly;
  final bool preferVideoCallUi;

  /// Matrix room id for this call (logical window identity with [callInstanceId]).
  final String roomId;

  /// Stable per [NativeLiveKitCallSession] (room + history id); not the OS window UUID.
  final String callInstanceId;
}

class DesktopIncomingCallWindowArgs {
  const DesktopIncomingCallWindowArgs({
    required this.roomId,
    required this.rtcEventId,
    required this.roomName,
    required this.callerLabel,
    this.callKitId,
    required this.isDarkMode,
  });

  final String roomId;
  final String rtcEventId;
  final String roomName;
  final String callerLabel;
  final String? callKitId;
  final bool isDarkMode;
}
