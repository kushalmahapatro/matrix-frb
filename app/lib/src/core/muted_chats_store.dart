import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-room mute: hides unread badges in the room list and suppresses local / sync / FCM
/// notifications for that room (client-side only).
class MutedChatsStore {
  MutedChatsStore._();
  static final MutedChatsStore instance = MutedChatsStore._();

  static const String storageKey = 'muted_room_ids_v1';

  final ValueNotifier<Set<String>> ids = ValueNotifier<Set<String>>({});

  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      final list = p.getStringList(storageKey) ?? [];
      ids.value = list.toSet();
    } catch (_) {
      ids.value = {};
    }
    _loaded = true;
  }

  bool isMuted(String roomId) {
    final id = roomId.trim();
    if (id.isEmpty) return false;
    return ids.value.contains(id);
  }

  Future<void> setMuted(String roomId, bool muted) async {
    await ensureLoaded();
    final id = roomId.trim();
    if (id.isEmpty) return;
    final next = Set<String>.from(ids.value);
    if (muted) {
      next.add(id);
    } else {
      next.remove(id);
    }
    ids.value = next;
    try {
      final p = await SharedPreferences.getInstance();
      final sorted = next.toList()..sort();
      await p.setStringList(storageKey, sorted);
    } catch (_) {}
  }
}
