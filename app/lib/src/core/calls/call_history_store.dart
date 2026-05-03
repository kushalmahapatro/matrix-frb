import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix_sdk/matrix_sdk.dart' show RoomDetails;
import 'package:shared_preferences/shared_preferences.dart';

enum CallHistoryDirection {
  outgoing,
  incoming,
}

/// One finished Matrix / Element Call session (local log only).
@immutable
class CallHistoryEntry {
  const CallHistoryEntry({
    required this.id,
    required this.roomId,
    required this.roomName,
    required this.isDirectRoom,
    required this.direction,
    required this.startedAt,
    required this.endedAt,
    required this.voiceOnly,
    required this.joinedExisting,
    required this.participantUserIds,
    required this.participantLabels,
    this.endReason,
  });

  final String id;
  final String roomId;
  final String roomName;
  final bool isDirectRoom;
  final CallHistoryDirection direction;
  final DateTime startedAt;
  final DateTime endedAt;
  final bool voiceOnly;
  final bool joinedExisting;

  /// User IDs seen in the RTC session when the call ended (best-effort).
  final List<String> participantUserIds;

  /// Display labels at end time (`userId` → label).
  final Map<String, String> participantLabels;

  /// Short outcome for missed / declined / no-answer rows (optional).
  final String? endReason;

  Duration get duration => endedAt.difference(startedAt);

  Map<String, dynamic> toJson() => {
        'id': id,
        'room_id': roomId,
        'room_name': roomName,
        'is_direct': isDirectRoom,
        'direction': direction.name,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt.toUtc().toIso8601String(),
        'voice_only': voiceOnly,
        'joined_existing': joinedExisting,
        'participant_user_ids': participantUserIds,
        'participant_labels': participantLabels,
        if (endReason != null && endReason!.isNotEmpty) 'end_reason': endReason,
      };

  static CallHistoryEntry? fromJson(Map<String, dynamic> j) {
    try {
      final dirName = j['direction']?.toString() ?? 'outgoing';
      final dir = CallHistoryDirection.values.firstWhere(
        (e) => e.name == dirName,
        orElse: () => CallHistoryDirection.outgoing,
      );
      final ids = (j['participant_user_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          <String>[];
      final labelsRaw = j['participant_labels'];
      final labels = <String, String>{};
      if (labelsRaw is Map) {
        labelsRaw.forEach((k, v) {
          labels[k.toString()] = v.toString();
        });
      }
      return CallHistoryEntry(
        id: j['id']?.toString() ?? '',
        roomId: j['room_id']?.toString() ?? '',
        roomName: j['room_name']?.toString() ?? '',
        isDirectRoom: j['is_direct'] == true,
        direction: dir,
        startedAt: DateTime.tryParse(j['started_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        endedAt: DateTime.tryParse(j['ended_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        voiceOnly: j['voice_only'] == true,
        joinedExisting: j['joined_existing'] == true,
        participantUserIds: ids,
        participantLabels: labels,
        endReason: j['end_reason']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

class _PendingSession {
  _PendingSession({
    required this.id,
    required this.roomId,
    required this.roomName,
    required this.isDirectRoom,
    required this.direction,
    required this.voiceOnly,
    required this.joinedExisting,
    required this.startedAt,
  });

  final String id;
  final String roomId;
  final String roomName;
  final bool isDirectRoom;
  final CallHistoryDirection direction;
  final bool voiceOnly;
  final bool joinedExisting;
  final DateTime startedAt;
}

/// Persists completed calls to [SharedPreferences] for the Calls tab.
class CallHistoryStore extends ChangeNotifier {
  CallHistoryStore._();
  static final CallHistoryStore instance = CallHistoryStore._();

  static const String _prefsKey = 'matrix_call_history_v1';
  static const int _maxEntries = 200;

  final Map<String, _PendingSession> _pending = {};
  List<CallHistoryEntry> _entries = [];
  bool _loaded = false;

  List<CallHistoryEntry> get entries => List.unmodifiable(_entries);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        final out = <CallHistoryEntry>[];
        for (final item in list) {
          if (item is Map) {
            final e = CallHistoryEntry.fromJson(Map<String, dynamic>.from(item));
            if (e != null &&
                e.roomId.isNotEmpty &&
                !e.endedAt.isBefore(e.startedAt)) {
              out.add(e);
            }
          }
        }
        out.sort((a, b) => b.startedAt.compareTo(a.startedAt));
        _entries = out;
      }
    } catch (_) {
      _entries = [];
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await p.setString(_prefsKey, encoded);
    } catch (_) {}
  }

  /// Call when the Element Call WebView/session is actually ready (URL loaded).
  void startSession({
    required String id,
    required String roomId,
    required String roomName,
    required bool isDirectRoom,
    required CallHistoryDirection direction,
    required bool voiceOnly,
    required bool joinedExisting,
  }) {
    final rid = roomId.trim();
    if (rid.isEmpty || id.isEmpty) return;
    _pending[id] = _PendingSession(
      id: id,
      roomId: rid,
      roomName: roomName.trim().isNotEmpty ? roomName.trim() : rid,
      isDirectRoom: isDirectRoom,
      direction: direction,
      voiceOnly: voiceOnly,
      joinedExisting: joinedExisting,
      startedAt: DateTime.now().toUtc(),
    );
  }

  /// Resolves RTC participant IDs + room member names; appends a history row.
  Future<void> endSession(
    String sessionId, {
    required String roomId,
    String? endReason,
  }) async {
    final pending = _pending.remove(sessionId);
    if (pending == null) return;

    final endedAt = DateTime.now().toUtc();
    final rid = roomId.trim().isEmpty ? pending.roomId : roomId.trim();

    RoomDetails? details;
    try {
      details = await MatrixService().client.getRoomDetails(roomId: rid);
    } catch (_) {}

    var participantIds = <String>[];
    try {
      participantIds = await MatrixService().client.activeCallParticipantIds(
        roomId: rid,
      );
    } catch (_) {}

    if (participantIds.isEmpty && details != null && details.isDirect) {
      participantIds = details.members
          .where((m) => !m.isSelf)
          .map((m) => m.userId.trim())
          .where((u) => u.isNotEmpty)
          .toList();
    }

    final labels = <String, String>{};
    if (details != null) {
      for (final m in details.members) {
        final uid = m.userId.trim();
        if (uid.isEmpty) continue;
        if (participantIds.isEmpty || participantIds.contains(uid)) {
          final label = m.displayName.trim().isNotEmpty
              ? m.displayName
              : m.userIdDisplay;
          labels[uid] = label;
        }
      }
    }

    for (final uid in participantIds) {
      labels.putIfAbsent(uid, () => uid);
    }

    if (participantIds.isEmpty && labels.isNotEmpty) {
      participantIds = labels.keys.toList();
    }

    final entry = CallHistoryEntry(
      id: pending.id,
      roomId: rid,
      roomName: pending.roomName,
      isDirectRoom: pending.isDirectRoom,
      direction: pending.direction,
      startedAt: pending.startedAt,
      endedAt: endedAt,
      voiceOnly: pending.voiceOnly,
      joinedExisting: pending.joinedExisting,
      participantUserIds: participantIds,
      participantLabels: labels,
      endReason: endReason,
    );

    _entries = [entry, ..._entries];
    if (_entries.length > _maxEntries) {
      _entries = _entries.sublist(0, _maxEntries);
    }
    await _persist();
    notifyListeners();
  }

  /// Drop pending state without writing history (e.g. bootstrap failed after marking).
  void abandonSession(String sessionId) {
    _pending.remove(sessionId);
  }

  Future<void> clearAll() async {
    _pending.clear();
    _entries = [];
    await _persist();
    notifyListeners();
  }

  /// Incoming call ended without connecting (missed, declined from system UI, etc.).
  Future<void> appendIncomingCallOutcome({
    required String roomId,
    required String roomName,
    required bool isDirectRoom,
    required bool voiceOnly,
    required String endReason,
  }) async {
    await ensureLoaded();
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now().toUtc();
    final entry = CallHistoryEntry(
      id: id,
      roomId: roomId.trim(),
      roomName: roomName.trim().isNotEmpty ? roomName.trim() : roomId,
      isDirectRoom: isDirectRoom,
      direction: CallHistoryDirection.incoming,
      startedAt: now,
      endedAt: now,
      voiceOnly: voiceOnly,
      joinedExisting: false,
      participantUserIds: const [],
      participantLabels: const {},
      endReason: endReason,
    );
    _entries = [entry, ..._entries];
    if (_entries.length > _maxEntries) {
      _entries = _entries.sublist(0, _maxEntries);
    }
    await _persist();
    notifyListeners();
  }
}
