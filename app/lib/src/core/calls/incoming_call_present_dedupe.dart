import 'dart:collection';

/// Dedupes [MatrixCallKitCoordinator.presentIncomingCall] when the same Matrix `event_id`
/// is delivered repeatedly (timeline rebuilds, sync retries).
class IncomingCallPresentDedupe {
  IncomingCallPresentDedupe({
    this.ttl = const Duration(seconds: 45),
    this.maxEntries = 64,
  });

  final Duration ttl;
  final int maxEntries;
  final LinkedHashMap<String, DateTime> _recentByEventId = LinkedHashMap();

  /// Empty [eventId] always returns `true` (no dedupe key — matches coordinator behavior).
  bool shouldPresentNow(String eventId, DateTime now) {
    final eid = eventId.trim();
    if (eid.isEmpty) return true;

    _recentByEventId.removeWhere((_, t) => now.difference(t) > ttl);
    final prev = _recentByEventId[eid];
    if (prev != null && now.difference(prev) < ttl) {
      return false;
    }
    _recentByEventId[eid] = now;
    while (_recentByEventId.length > maxEntries) {
      _recentByEventId.remove(_recentByEventId.keys.first);
    }
    return true;
  }

  /// Clears dedupe memory (logout / tests).
  void clearDedupeEntries() => _recentByEventId.clear();
}
