import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

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
  }) = _Chat;

  String get formatTime {
    if (lastActivity == null) {
      return '';
    }

    final now = DateTime.now();
    final difference = now.difference(lastActivity!);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }
}

enum ChatRoomStatus { joined, left, invited, knocked, banned }

enum ChatType { all, invited, direct, group }
