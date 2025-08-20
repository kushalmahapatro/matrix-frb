import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:matrix/src/core/domain/services/app_config.dart';
import 'package:matrix/src/rust/matrix/timelines.dart';

part 'conversation_state.freezed.dart';

@freezed
abstract class ConversationState with _$ConversationState {
  const factory ConversationState.loading() = ConversationStateLoading;
  const factory ConversationState.waitingForInvite() =
      ConversationStateWaitingForInvite;
  const factory ConversationState.loaded({
    required List<Message> messages,
    required ConversationInfo roomInfo,
  }) = RoomStateLoaded;
  const factory ConversationState.error({required String message}) =
      RoomStateError;
}

@freezed
abstract class ConversationInfo with _$ConversationInfo {
  const factory ConversationInfo({
    required String id,
    required String name,
    required String topic,
    required int memberCount,
    @Default(false) bool isDirect,
    String? avatarUrl,
  }) = _ConversationInfo;
}

enum MessageType { text, image, file, system }

extension MessageExtension on Message {
  String get displayName => sender.replaceAll(AppConfig.homeserverUrl.host, '');

  DateTime get dateTime {
    // Convert timestamp to DateTime
    final timestamp = this.timestamp.toInt();
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${dateTime.day}/${dateTime.month} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  // Format date as needed, e.g., "MMM dd, yyyy"
}
