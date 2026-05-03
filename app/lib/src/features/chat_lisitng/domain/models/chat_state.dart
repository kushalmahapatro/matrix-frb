import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:matrix_sdk/matrix_sdk.dart';

part 'chat_state.freezed.dart';

@freezed
abstract class ChatState with _$ChatState {
  const factory ChatState.loading() = ChatStateLoading;
  const factory ChatState.loaded({required List<Chat> rooms}) = ChatStateLoaded;
  const factory ChatState.error({required String message}) = ChatStateError;
}

@freezed
abstract class Chat with _$Chat {
  const Chat._();

  const factory Chat({
    required String id,
    required String name,
    required String lastMessage,
    required ChatRoomStatus status,
    DateTime? lastActivity,
    @Default(0) int unreadCount,
    @Default(false) bool isDirect,
    String? avatarUrl,
    /// Last timeline message from Rust (media kind, event id for thumbnails, mimetype).
    @Default(null) Message? lastPreview,
  }) = _Chat;

  /// Titles the Matrix SDK uses for a DM when there is no peer to name (e.g. they left).
  static bool isArchivedDirectRoomDisplayName(String name) {
    final t = name.trim().toLowerCase();
    if (t.isEmpty) return true;
    return t == 'empty chat' || t == 'empty room';
  }

  /// Rooms to hide from "all" / direct / group and show under the LEFT tab.
  /// Includes explicit [ChatRoomStatus.left] / banned and joined DMs with placeholder titles.
  bool get isArchivedForListing {
    if (status == ChatRoomStatus.left || status == ChatRoomStatus.banned) {
      return true;
    }
    if (!isDirect) return false;
    if (status == ChatRoomStatus.invited || status == ChatRoomStatus.knocked) {
      return false;
    }
    return Chat.isArchivedDirectRoomDisplayName(name);
  }

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  String get formatTime {
    if (lastActivity == null) return '';

    final t = lastActivity!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final activityDay = DateTime(t.year, t.month, t.day);
    final daysDiff = today.difference(activityDay).inDays;

    if (daysDiff == 0) {
      final hour12 = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
      final ampm = t.hour < 12 ? 'AM' : 'PM';
      return '$hour12:${t.minute.toString().padLeft(2, '0')} $ampm';
    }
    if (daysDiff > 0 && daysDiff < 7) {
      return _weekdays[t.weekday - 1];
    }
    return '${t.day}/${t.month}/${t.year}';
  }
}

enum ChatRoomStatus { joined, left, invited, knocked, banned }

enum ChatType { all, invited, direct, group, left }
