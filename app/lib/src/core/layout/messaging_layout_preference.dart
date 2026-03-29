import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/layout/app_layout_variant.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPrefsKey = 'messaging_conversation_layout';

/// Room list + open chat (columns) vs stacked full-screen navigation — not bubble alignment.
enum MessagingLayoutPreference {
  /// Desktop + portrait phone (wide enough) → columns; else stacked navigator.
  auto,
  split,
  /// One pane at a time (list then room, like typical mobile stacks).
  threaded,
}

extension MessagingLayoutPreferenceStorage on MessagingLayoutPreference {
  static MessagingLayoutPreference? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final v in MessagingLayoutPreference.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// Loads/saves [MessagingLayoutPreference] and notifies listeners.
class MessagingLayoutPreferenceNotifier extends ChangeNotifier {
  MessagingLayoutPreference _value = MessagingLayoutPreference.auto;

  MessagingLayoutPreference get value => _value;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final stored = MessagingLayoutPreferenceStorage.tryParse(
      p.getString(_kPrefsKey),
    );
    if (stored != null && stored != _value) {
      _value = stored;
      notifyListeners();
    }
  }

  Future<void> set(MessagingLayoutPreference v) async {
    if (_value == v) return;
    _value = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrefsKey, v.name);
  }
}

/// `true` when we treat the device as a handheld phone (not tablet / desktop).
bool _isHandheldPhonePortrait(MediaQueryData mq) {
  if (isDesktopTargetPlatform() || kIsWeb) return false;
  if (mq.orientation != Orientation.portrait) return false;
  return mq.size.shortestSide < 600;
}

/// Resolves list/detail vs compact stack from media query + user preference.
AppLayoutVariant resolveMessagingLayoutVariant({
  required MediaQueryData mq,
  required MessagingLayoutPreference preference,
}) {
  switch (preference) {
    case MessagingLayoutPreference.threaded:
      return AppLayoutVariant.compact;
    case MessagingLayoutPreference.split:
      if (mq.size.width < 480) {
        return AppLayoutVariant.compact;
      }
      return AppLayoutVariant.split;
    case MessagingLayoutPreference.auto:
      // Native desktop: master–detail (list | conversation), not a mobile stack.
      if (isDesktopTargetPlatform()) {
        if (mq.size.width < 480) return AppLayoutVariant.compact;
        return AppLayoutVariant.split;
      }
      if (_isHandheldPhonePortrait(mq)) {
        if (mq.size.width < 480) return AppLayoutVariant.compact;
        return AppLayoutVariant.split;
      }
      return AppLayoutVariant.compact;
  }
}
