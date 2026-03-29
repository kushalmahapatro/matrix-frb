import 'dart:convert';

import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';

/// JSON payload in [WindowController.arguments] for [desktop_multi_window].
///
/// Main window uses an empty string; extra engines pass encoded JSON.
abstract final class DesktopWindowArgs {
  static const String typeKey = 't';
  static const String typeConversation = 'conversation';

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
