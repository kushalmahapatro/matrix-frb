/// Rooms whose conversation UI is currently mounted (split-pane may have several).
class NotificationForegroundScope {
  NotificationForegroundScope._();

  static final Set<String> _visibleRoomIds = <String>{};

  static void registerVisibleRoom(String roomId) {
    final id = roomId.trim();
    if (id.isEmpty) return;
    _visibleRoomIds.add(id);
  }

  static void unregisterVisibleRoom(String roomId) {
    _visibleRoomIds.remove(roomId.trim());
  }

  static bool isRoomForegroundVisible(String roomId) =>
      _visibleRoomIds.contains(roomId.trim());
}
