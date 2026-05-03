import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Same window as [RTC_INCOMING_RING_NOTIFY_MAX_AGE_MS] in the Rust SDK (120s).
const Duration rtcIncomingRingMaxAge = Duration(seconds: 120);

const String _androidChannelId = 'matrix_messages';
const String _androidChannelName = 'Matrix';

String _notificationGroupKey(String roomId) {
  final id = roomId.trim();
  if (id.isEmpty) return 'matrix_other';
  return 'matrix_room_$id';
}

/// Shows a tray notification for a missed call without importing [MatrixNotificationsCoordinator]
/// (avoids a circular import with [MatrixCallKitCoordinator]).
class MissedCallTrayNotifier {
  MissedCallTrayNotifier._();
  static final MissedCallTrayNotifier instance = MissedCallTrayNotifier._();

  FlutterLocalNotificationsPlugin? _local;
  int _serial = 0;

  void attach(FlutterLocalNotificationsPlugin plugin) {
    _local = plugin;
  }

  Future<void> showMissedCall({
    required String roomId,
    String? roomTitle,
    String? callerLabel,
  }) async {
    if (kIsWeb) return;
    final local = _local;
    if (local == null) return;

    final title = (roomTitle != null && roomTitle.trim().isNotEmpty)
        ? roomTitle.trim()
        : (roomId.trim().isNotEmpty ? roomId : 'Matrix');
    final who = callerLabel?.trim() ?? '';
    final body = who.isNotEmpty ? 'Missed call from $who' : 'Missed call';

    _serial = (_serial + 1) & 0x7fffffff;
    if (_serial == 0) _serial = 1;
    final notificationId = _serial;

    final groupKey = _notificationGroupKey(roomId);
    final android = AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      channelDescription: 'Matrix messages and invites',
      icon: 'ic_stat_matrix',
      importance: Importance.high,
      priority: Priority.high,
      groupKey: groupKey,
      setAsGroupSummary: false,
      groupAlertBehavior: GroupAlertBehavior.all,
    );
    final darwin = DarwinNotificationDetails(threadIdentifier: groupKey);
    final details = NotificationDetails(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );

    await local.show(
      notificationId,
      title,
      body,
      details,
      payload: roomId.trim().isNotEmpty ? roomId : null,
    );
  }
}
