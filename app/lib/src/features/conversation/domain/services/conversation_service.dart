import 'package:matrix/src/features/conversation/domain/models/conversation_state.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix_sdk/matrix_sdk.dart';
import 'package:result_dart/result_dart.dart';

class ConversationService {
  ConversationService({required this.matrixService});
  final MatrixService matrixService;

  Future<Result<List<Message>>> loadMessages(String roomId) async {
    try {
      final messages = await matrixService.client.getTimelineItemsByRoomId(
        roomId: roomId,
      );
      return Success(messages);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  Stream<MessageUpdate> subscribeToTimelineUpdates(String roomId) {
    return matrixService.client.subscribeToTimelineUpdates(roomId: roomId);
  }

  /// Canonical message list for the room from Rust (full list on every change).
  Stream<List<Message>> subscribeToTimelineList(String roomId) {
    return matrixService.client.subscribeToTimelineList(roomId: roomId);
  }

  Future<ConversationInfo> loadRoomInfo() async {
    return ConversationInfo(
      id: '1',
      name: 'Test Room',
      topic: 'Test Topic',
      memberCount: 10,
    );
  }

  /// Returns event_id on success. After success, call [takeLastSentRoomUpdate] and push the
  /// room update so the room list shows the sent message as last (requires codegen to be run).
  Future<Result<String>> sendMessage(String roomId, String content) async {
    try {
      final eventId = await matrixService.client.sendMessage(
        roomId: roomId,
        content: content,
      );
      return Success(eventId);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  /// Room update for the last sent message. Call after [sendMessage] succeeds.
  /// Requires flutter_rust_bridge_codegen to be run so [MatrixClient.takeLastSentRoomUpdate] exists.
  Future<RoomUpdate?> takeLastSentRoomUpdate() async {
    return matrixService.client.takeLastSentRoomUpdate();
  }

  Future<Result<String>> acceptInvite(String roomId) async {
    try {
      final result = await matrixService.client.joinRoom(roomId: roomId);
      return Success(result);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  Future<Result<String>> rejectInvite(String roomId) async {
    try {
      final result = await matrixService.client.leaveRoom(roomId: roomId);
      return Success(result);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  Future<Result<List<Message>>> fetchOlderMessages({
    required String roomId,
    int count = 50,
  }) async {
    try {
      final previousMessages = await matrixService.client.getOlderMessages(
        roomId: roomId,
        count: count,
      );
      return Success(previousMessages);
    } catch (e) {
      return Failure(Exception(e));
    }
  }
}
