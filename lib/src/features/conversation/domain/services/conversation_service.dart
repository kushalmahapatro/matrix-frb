import 'package:matrix/src/features/conversation/domain/models/conversation_state.dart';
import 'package:matrix/src/rust/matrix/timelines.dart' as timelines;
import 'package:matrix/src/rust/matrix/rooms.dart' as rooms;
import 'package:result_dart/result_dart.dart';

class ConversationService {
  Future<Result<List<timelines.Message>>> loadMessages(String roomId) async {
    try {
      final messages = await timelines.getTimelineItemsByRoomId(roomId: roomId);
      return Success(messages);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  Stream<timelines.MessageUpdate> subscribeToTimelineUpdates(String roomId) {
    return timelines.subscribeToTimelineUpdates(roomId: roomId);
  }

  Future<ConversationInfo> loadRoomInfo() async {
    return ConversationInfo(
      id: '1',
      name: 'Test Room',
      topic: 'Test Topic',
      memberCount: 10,
    );
  }

  Future<Result<String>> sendMessage(String roomId, String content) async {
    try {
      final result = await rooms.sendMessage(roomId: roomId, content: content);
      return Success(result);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  Future<Result<String>> acceptInvite(String roomId) async {
    try {
      final result = await rooms.joinRoom(roomId: roomId);
      return Success(result);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  Future<Result<String>> rejectInvite(String roomId) async {
    try {
      final result = await rooms.leaveRoom(roomId: roomId);
      return Success(result);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  Future<Result<List<timelines.Message>>> fetchOlderMessages({
    required String roomId,
    int count = 20,
  }) async {
    try {
      final previousMessages = await timelines.getOlderMessages(
        roomId: roomId,
        count: count,
      );
      return Success(previousMessages);
    } catch (e) {
      return Failure(Exception(e));
    }
  }
}
