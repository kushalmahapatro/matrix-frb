import 'package:flutter/foundation.dart';
import 'package:matrix_sdk/matrix_sdk.dart' show Message;
import 'package:shared_preferences/shared_preferences.dart';

/// Matrix has no server-side “delete for me” for room messages; we persist hidden
/// event / transaction ids locally (this device only).
class TimelineLocalHiddenStore {
  TimelineLocalHiddenStore._();

  static const _prefsKey = 'matrix.timeline_locally_hidden_keys';

  static final Set<String> _keys = {};
  static bool _loaded = false;

  /// Bumped after [hideMessage] so UI can rebuild without a new timeline snapshot.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    _keys.addAll(p.getStringList(_prefsKey) ?? const []);
    _loaded = true;
  }

  static Future<void> hideMessage(Message m) async {
    await ensureLoaded();
    final p = await SharedPreferences.getInstance();
    if (m.eventId.isNotEmpty) {
      _keys.add('e:${m.eventId}');
    }
    if (m.transactionId.isNotEmpty) {
      _keys.add('t:${m.transactionId}');
    }
    await p.setStringList(_prefsKey, _keys.toList());
    revision.value = revision.value + 1;
  }

  static bool isHidden(Message m) {
    return isHiddenEventOrTransaction(
      eventId: m.eventId,
      transactionId: m.transactionId,
    );
  }

  /// Same keys as [hideMessage] — for rows that are not a full [Message] (e.g. room info index).
  static bool isHiddenEventOrTransaction({
    String eventId = '',
    String transactionId = '',
  }) {
    if (eventId.isNotEmpty && _keys.contains('e:$eventId')) {
      return true;
    }
    if (transactionId.isNotEmpty && _keys.contains('t:$transactionId')) {
      return true;
    }
    return false;
  }
}
