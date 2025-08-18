import 'package:matrix/src/rust/matrix/rooms.dart' as rooms;
import 'package:result_dart/result_dart.dart';

class ChatServices {
  const ChatServices();

  Future<Result<List<rooms.RoomUpdate>>> loadRooms() async {
    try {
      final result = await rooms.getAllRooms();
      return Success(result);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  Stream<rooms.RoomUpdate> subscribeToAllRoomUpdates() {
    return rooms.subscribeToAllRoomUpdates().map((roomUpdate) => roomUpdate);
  }
}
