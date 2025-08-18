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
}
