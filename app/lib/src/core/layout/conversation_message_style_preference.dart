import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPrefsKey = 'messaging_message_style';

/// How message bubbles are placed in the timeline (not the room-list workspace).
enum ConversationMessageStyle {
  /// Same as [leftRight] today (classic chat).
  auto,
  /// All bubbles align from the start; incoming vs outgoing still differ by color, bar, names.
  threaded,
  /// Outgoing on one side, incoming on the other.
  leftRight,
}

extension ConversationMessageStyleStorage on ConversationMessageStyle {
  static ConversationMessageStyle? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final v in ConversationMessageStyle.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// Persists [ConversationMessageStyle] for the conversation timeline.
class ConversationMessageStyleNotifier extends ChangeNotifier {
  ConversationMessageStyle _value = ConversationMessageStyle.auto;

  ConversationMessageStyle get value => _value;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final stored = ConversationMessageStyleStorage.tryParse(
      p.getString(_kPrefsKey),
    );
    if (stored != null && stored != _value) {
      _value = stored;
      notifyListeners();
    }
  }

  Future<void> set(ConversationMessageStyle v) async {
    if (_value == v) return;
    _value = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrefsKey, v.name);
  }
}

/// When `true`, use classic opposite-side placement; when `false`, threaded (start-aligned).
bool conversationUsesLeftRightPlacement(ConversationMessageStyle preference) {
  switch (preference) {
    case ConversationMessageStyle.threaded:
      return false;
    case ConversationMessageStyle.leftRight:
    case ConversationMessageStyle.auto:
      return true;
  }
}
