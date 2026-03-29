import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/desktop/desktop_window_args.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:provider/provider.dart';

/// Opens a **native** conversation window via [desktop_multi_window] (separate
/// Flutter engine). Requires runner hooks — see `macos/Runner/MainFlutterWindow.swift`,
/// `windows/runner/flutter_window.cpp`, `linux/runner/my_application.cc`.
///
/// Returns `false` on web/mobile or if window creation fails.
Future<bool> openConversationInNewDesktopWindow({
  required BuildContext context,
  required Chat chat,
}) async {
  if (kIsWeb || !isDesktopTargetPlatform()) return false;

  var isDark = true;
  try {
    isDark = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
  } catch (_) {}

  try {
    final controller = await WindowController.create(
      WindowConfiguration(
        arguments: DesktopWindowArgs.encodeConversation(
          roomId: chat.id,
          roomName: chat.name,
          status: chat.status,
          isDarkMode: isDark,
        ),
        hiddenAtLaunch: true,
      ),
    );
    await controller.show();
    return true;
  } catch (e, st) {
    debugPrint('openConversationInNewDesktopWindow: $e\n$st');
    return false;
  }
}
