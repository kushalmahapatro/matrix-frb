import 'dart:typed_data';

import 'package:elementary/elementary.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix/src/core/timeline_local_hidden_store.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix_sdk/matrix_sdk.dart'
    show Message, RoomMessageKind, RoomUpdate;
import 'package:result_dart/result_dart.dart';

String messagingRoomListLastMessageLine(Message? message) {
  if (message == null) return '';
  if (message.isRedacted) return 'Message deleted';
  if (TimelineLocalHiddenStore.isHidden(message)) {
    return 'Message removed on this device';
  }
  final body = message.content.trim();
  if (body.isEmpty &&
      message.roomMsgKind == RoomMessageKind.other &&
      message.pollOptionsJson.trim().isEmpty &&
      message.mediaMimetype.trim().isEmpty) {
    // Latest timeline row can be m.room.member / other state mirrored as
    // [RoomMessageKind.other] with no body (see Rust is_usable_room_list_preview_message).
    return 'Room updated';
  }
  return message.content;
}

class MessagingRoomListModel extends ElementaryModel {
  MessagingRoomListModel(this._matrixService) : super();
  final MatrixService _matrixService;

  Future<Uint8List?> loadListingThumbnail(String roomId, Message message) async {
    if (message.isRedacted) return null;
    if (TimelineLocalHiddenStore.isHidden(message)) return null;
    final id = message.eventId.isNotEmpty
        ? message.eventId
        : message.transactionId;
    if (id.isEmpty) return null;
    try {
      return await _matrixService.client.fetchRoomMessageMedia(
        roomId: roomId,
        eventId: id,
        thumbnail: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<Chat>> loadRooms() async {
    Result<List<RoomUpdate>> result;
    try {
      final response = await _matrixService.client.getAllRooms();
      result = Success(response);
    } catch (e) {
      result = Failure(Exception(e));
    }
    return result.fold(
      (success) => success
          .map(
            (room) => Chat(
              id: room.roomId,
              name: room.displayName ?? room.rawName ?? '',
              lastMessage: messagingRoomListLastMessageLine(room.message),
              lastActivity:
                  (room.message?.timestamp ?? BigInt.from(0)) > BigInt.from(0)
                  ? DateTime.fromMillisecondsSinceEpoch(
                      room.message!.timestamp.toInt(),
                    )
                  : null,
              isDirect: room.isDm ?? false,
              unreadCount: room.unreadMessages?.toInt() ?? 0,
              status: ChatRoomStatus.values.firstWhere(
                (status) => status.name == room.updateType.name,
              ),
              avatarUrl: room.avatarUrl,
              lastPreview: room.message,
            ),
          )
          .toList(),
      (failure) {
        LoggingService.error(
          'MESSAGING_WORKSPACE',
          'Failed to load rooms: $failure',
        );
        return [];
      },
    );
  }

  Stream<List<Chat>> subscribeToRoomList() {
    return _matrixService.client
        .subscribeToRoomList()
        .map(_roomUpdatesToChatList);
  }

  static List<Chat> _roomUpdatesToChatList(List<RoomUpdate> updates) {
    return updates.map(_roomUpdateToChat).toList();
  }

  static Chat _roomUpdateToChat(RoomUpdate roomUpdate) {
    return Chat(
      id: roomUpdate.roomId,
      name: roomUpdate.displayName ?? roomUpdate.rawName ?? '',
      lastMessage: messagingRoomListLastMessageLine(roomUpdate.message),
      lastActivity:
          (roomUpdate.message?.timestamp ?? BigInt.from(0)) > BigInt.from(0)
              ? DateTime.fromMillisecondsSinceEpoch(
                  roomUpdate.message!.timestamp.toInt(),
                )
              : null,
      isDirect: roomUpdate.isDm ?? false,
      unreadCount: roomUpdate.unreadMessages?.toInt() ?? 0,
      status: ChatRoomStatus.values.firstWhere(
        (status) => status.name == roomUpdate.updateType.name,
      ),
      avatarUrl: roomUpdate.avatarUrl,
      lastPreview: roomUpdate.message,
    );
  }

  Future<Uint8List?> loadRoomAvatarThumbnail(String mxcUri) async {
    final t = mxcUri.trim();
    if (t.isEmpty) return null;
    try {
      return await _matrixService.client.fetchUserAvatarThumbnail(mxcUri: t);
    } catch (_) {
      return null;
    }
  }
}
